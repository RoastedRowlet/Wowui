-- =========================================================
-- ExwindGUI.lua
-- 封装 LibSharedMedia (LSM) 的原生 Wow 工具组件
-- =========================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end

-- 确保 EXUI 命名空间存在（可能在 ExwindToolsUI.lua 之前加载）
local EXUI = ExwindTools.UI or {}
ExwindTools.UI = EXUI
_G.ExwindToolsUI = EXUI

local LSM = LibStub("LibSharedMedia-3.0")
local L = ExwindTools.L

-- [Core] 严格遵照指令：只许使用游戏默认字体路径，禁止任何硬编码引用
local defaultFontPath, defaultFontSize, defaultFontFlags = _G.GameFontHighlight:GetFont()

-- DropdownButton 的箭头、文字与背景切片以 30px 为一组固定几何。
-- Grid 可以决定它在逻辑网格中占几格，但不能把物理按钮高度拉伸；
-- 否则右侧箭头仍维持模板尺寸，视觉会变形。LSM 与普通下拉共用此几何约束，
-- 数据/菜单实现仍各自独立。
EXUI.GridDropdownHeight = 30

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
    dropdown:SetSize(width, EXUI.GridDropdownHeight)
    dropdown._exGridFixedHeight = EXUI.GridDropdownHeight
end

-- DropdownButton 的菜单不是子 Frame，而是暴雪 Menu 系统按“按钮自身”的 strata
-- 单独创建。池化控件会保留上一次的 strata；若不在这里同步，组合弹窗虽然在
-- TOOLTIP 层，里面的下拉菜单仍可能以 MEDIUM 层打开并被弹窗遮住。
local function SyncDropdownMenuLayer(dropdown, parent)
    if not dropdown or not dropdown.SetFrameStrata then return end
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

-- [Helper] 防止 UI 污染的统一清理函数
local function CleanDropdownButton(button)
    if button.playBtn then button.playBtn:Hide() end
    if button.fontString then
        button.fontString:SetAlpha(1)
        button.fontString:SetFontObject("GameFontHighlight")
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
local EXTERNAL_DROPDOWN_SEARCH_HEIGHT = 25
local EXTERNAL_DROPDOWN_SEARCH_MASK_HEIGHT = 4

local function AddSearchSpacer(rootDescription)
    local spacer = rootDescription:CreateButton("")
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
        dropdown:SetMenuAnchor(AnchorUtil.CreateAnchor("TOPLEFT", dropdown, "BOTTOMLEFT", 0, 0))
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

    local background = EXUI:CreateVisualTexture(frame, EXBASEFRAME)
    background:SetAllPoints()
    background:SetTexture("Interface\\Buttons\\WHITE8X8")
    background:SetColorTexture(0, 0, 0, 1)
    frame.Background = background

    local bottomMask = EXUI:CreateVisualTexture(frame, EXBASEFRAME)
    bottomMask:SetTexture("Interface\\Buttons\\WHITE8X8")
    bottomMask:SetColorTexture(0, 0, 0, 1)
    bottomMask:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, 0)
    bottomMask:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    bottomMask:SetHeight(EXTERNAL_DROPDOWN_SEARCH_MASK_HEIGHT)
    frame.BottomMask = bottomMask

    local topMask = EXUI:CreateVisualTexture(frame, EXBASEFRAME)
    topMask:SetTexture("Interface\\Buttons\\WHITE8X8")
    topMask:SetColorTexture(0, 0, 0, 1)
    topMask:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 0)
    topMask:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, 0)
    topMask:SetHeight(EXTERNAL_DROPDOWN_SEARCH_MASK_HEIGHT)
    topMask:Hide()
    frame.TopMask = topMask

    local searchBox = CreateFrame("EditBox", nil, frame, "BackdropTemplate")
    searchBox:SetPoint("TOPLEFT", 0, 0)
    searchBox:SetPoint("BOTTOMRIGHT", 0, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(64)
    searchBox:SetFont(defaultFontPath, 14, defaultFontFlags)
    if searchBox.SetBackdrop then
        searchBox:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        searchBox:SetBackdropColor(0.08, 0.08, 0.08, 1)
        searchBox:SetBackdropBorderColor(0.32, 0.32, 0.32, 1)
    end
    local searchIcon = EXUI:CreateVisualTexture(searchBox, EXBASEFRAME)
    searchIcon:SetSize(14, 14)
    searchIcon:SetPoint("LEFT", 7, 0)
    searchIcon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    searchIcon:SetVertexColor(0.55, 0.55, 0.55, 1)
    local instructions = EXUI:CreateVisualFontString(searchBox, EXFONTFRAME)
    instructions:SetFont(defaultFontPath, 14, defaultFontFlags)
    instructions:SetTextColor(0.42, 0.42, 0.42, 1)
    instructions:SetPoint("LEFT", 26, 0)
    instructions:SetText(SEARCH)
    searchBox.Instructions = instructions
    searchBox:SetTextInsets(26, 6, 0, 0)
    local clearBtn = CreateFrame("Button", nil, searchBox)
    clearBtn:SetSize(14, 14)
    clearBtn:SetPoint("RIGHT", -5, 0)
    clearBtn:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
    clearBtn:GetNormalTexture():SetVertexColor(0.55, 0.55, 0.55)
    clearBtn:SetHighlightTexture("Interface\\Buttons\\UI-StopButton")
    clearBtn:GetHighlightTexture():SetVertexColor(0.9, 0.9, 0.9)
    clearBtn:Hide()
    clearBtn:SetScript("OnClick", function()
        searchBox:SetText("")
        searchBox:SetFocus()
    end)
    searchBox.ClearButton = clearBtn
    frame.SearchBox = searchBox

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
            self:SetPoint("TOP", menu, "TOP", 0, -4)
        elseif opensUpward then
            self:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 0, 0)
        else
            self:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, 0)
        end
        self:SetWidth(math.max(menu and menu:GetWidth() or 0, dropdown:GetWidth() or 0, 180) * 0.95)
        self.BottomMask:SetShown(false)
        self.TopMask:SetShown(opensUpward)
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
        self.SearchBox:SetHeight(EXTERNAL_DROPDOWN_SEARCH_HEIGHT)
        -- 动态同步菜单背景色
        local menu = dropdown and dropdown.menu
        if self.SearchBox and self.SearchBox.SetBackdropColor then
            local br, bg, bb, ba
            if menu and type(menu.GetBackdropColor) == "function" then
                br, bg, bb, ba = menu:GetBackdropColor()
            end
            if br then
                self.SearchBox:SetBackdropColor(br, bg, bb, ba or 1)
            end
            -- 边框透明，消除视觉分割
            self.SearchBox:SetBackdropBorderColor(0, 0, 0, 0)
        end
        self:AnchorToDropdown(dropdown)
        self:Show()
        self.SearchBox:SetText(dropdown._searchText or "")
        self.SearchBox:SetCursorPosition(string.len(self.SearchBox:GetText() or ""))
        C_Timer.After(0, function()
            if self:IsShown() and self.ownerDropdown == dropdown then
                self:AnchorToDropdown(dropdown)
                self.SearchBox:SetFocus()
                self.SearchBox:SetCursorPosition(string.len(self.SearchBox:GetText() or ""))
            end
        end)
    end

    function frame:HideForDropdown(dropdown)
        if dropdown and self.ownerDropdown ~= dropdown then
            return
        end

        self.ownerDropdown = nil
        self:SetParent(UIParent)
        self.SearchBox:ClearFocus()
        self.SearchBox:SetText("")
        self:Hide()
    end

    frame.SearchBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        if self.Instructions then self.Instructions:SetShown(text == "") end
        if self.ClearButton then self.ClearButton:SetShown(text ~= "") end
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
        dropdown:SetMenuAnchor(AnchorUtil.CreateAnchor("TOPLEFT", dropdown, "BOTTOMLEFT", 0, 0))
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

    -- 1. 寻找 Label 对象 (不同组件存储位置不同，统统找出来)
    local label = widget.labelText or widget.label or widget.Title
    if not label or not label.SetFont then return end

    -- 保存引用以便后续再次访问
    widget._exLabel = label

    -- 2. [Fix v4.3.4] 恢复使用 SetFont 配合 CJK 探测后的 MAIN_FONT
    local fontSize = tonumber(size) or 16
    local fontPath = ExwindTools.MAIN_FONT

    label:SetFont(fontPath, fontSize, "OUTLINE")

    -- [v4.3.1] 级联更新子物料
    if widget.SetFont then
        if widget:GetObjectType() == "EditBox" then
            widget:SetFontObject("ChatFontNormal") -- 输入框专用
        else
            widget:SetFont(fontPath, fontSize, "OUTLINE")
        end
    end
    if widget.nameText then -- itemconfig 特供
        widget.nameText:SetFontObject("GameFontNormalLarge")
    end

    -- [Fix] 判定逻辑统一，支持池化后的名称 (GridCheckbox / GridSlider 等)
    local gType = widget._gridType and widget._gridType:lower() or ""

    -- 3. 特殊组件位置锁定 (对于 FontGroup/Header 等，只改字体，不移动位置)
    if gType:find("fontgroup") or gType:find("header") or gType:find("soundgroup") or gType:find("modulecommonsettings")
        or gType:find("description") or gType:find("card") then
        return
    end

    -- 4. 判定 Checkbox/Slider 特殊逻辑

    -- 对于 Checkbox，由于它是 [Box] [Label] 结构，特殊处理
    if gType == "checkbox" or gType == "gridcheckbox" then
        label:ClearAllPoints()
        if pos == "left" then
            label:SetPoint("RIGHT", widget.checkbox, "LEFT", -5, 0)
            label:SetJustifyH("RIGHT")
        elseif pos == "top" then
            label:SetPoint("BOTTOMLEFT", widget.checkbox, "TOPLEFT", 0, 2)
            label:SetJustifyH("LEFT")
        else -- right (Default)
            label:SetPoint("LEFT", widget.checkbox, "RIGHT", 6, 0)
            label:SetJustifyH("LEFT")
        end
        return
    end

    -- [Fix] 对于 Slider，必需保持 Title 不覆盖 ValueText 的约束
    if gType == "slider" or gType == "gridslider" then
        label:ClearAllPoints()
        if pos == "left" then
            label:SetPoint("RIGHT", widget, "LEFT", -5, 0)
            label:SetJustifyH("RIGHT")
        else -- top (Default)
            label:SetPoint("BOTTOMLEFT", widget, "TOPLEFT", 0, 1)
            if widget.ValueText then
                label:SetPoint("RIGHT", widget.ValueText, "LEFT", -5, 0)
            end
            label:SetJustifyH("LEFT")
            label:SetWordWrap(false)
        end
        return
    end

    -- [Fix] 对于特定的组组件，不碰位置
    if gType == "fontgroup" or gType == "gridfontgroup" or gType == "header" or gType == "gridheader"
        or gType == "soundgroup" or gType == "subheader" or gType == "gridsubheader" or gType == "icongroup" or gType == "glow_settings"
        or gType == "color" or gType == "colorbutton" or gType == "gridcolorbutton"
        or gType == "description" or gType == "griddescription" or gType == "card" or gType == "gridcard" then
        return
    end

    -- 通用处理 (Input, Dropdown, Button 等)
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
        dropdown.labelText = EXUI:CreateVisualFontString(dropdown, EXFONTFRAME, "GameFontHighlight")
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
    dropdown.labelText:SetText(label or "")

    -- [v4.3.2 Fix] 将状态挂载到 Self，避免 SetupMenu 闭包捕获导致内存泄漏
    dropdown._currentValue = currentValue
    dropdown._onSelect = onSelect
    dropdown._items = items
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
        rootDescription:SetScrollMode(400)
        if self._externalSearchEnabled then AddSearchSpacer(rootDescription) end

        local function BuildMenu(rootDesc, list)
            if not list then return end -- [Fix] 防止复用初始化间隙导致的 nil 报错
            for _, item in ipairs(list) do
                if type(item) == "table" and item.isMenu then
                    local subMenu = rootDesc:CreateButton(item.text, function() end)
                    BuildMenu(subMenu, item.menu)
                else
                    local text, value
                    if type(item) == "table" then
                        text, value = item[1], item[2]
                    else
                        text, value = item, item
                    end

                    rootDesc:CreateRadio(text,
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
                end
            end
        end

        local filteredItems = FilterDropdownItems(self._items, self._searchText)
        if filteredItems and #filteredItems > 0 then
            BuildMenu(rootDescription, filteredItems)
        else
            rootDescription:CreateTitle(L["无匹配结果"])
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
        dropdown.labelText = EXUI:CreateVisualFontString(dropdown, EXFONTFRAME, "GameFontHighlight")
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
    dropdown.labelText:SetText(label or "")

    -- [v4.3.2 Fix] 将状态挂载到 Self
    dropdown._selectedValue = currentValue or LSM:GetDefault(mediaType)
    dropdown._onSelect = onSelect
    dropdown._mediaType = mediaType
    SetDropdownSearchEnabled(dropdown, searchConfig)

    SetDropdownDisplayText(dropdown, dropdown._selectedValue)

    dropdown:SetupMenu(function(self, rootDescription)
        if not self._mediaType then return end -- [Fix] 防止复用时 nil 报错
        if self._externalSearchEnabled then AddSearchSpacer(rootDescription) else rootDescription:CreateTitle(L["选择"] .. (self._mediaType == "font" and L["字体"] or self._mediaType)) end
        if rootDescription.SetScrollMode then rootDescription:SetScrollMode(400) end

        local list = LSM:HashTable(self._mediaType)
        local sortedKeys = LSM:List(self._mediaType)
        local searchNeedle = NormalizeDropdownSearchText(self._searchText)
        local hasMatch = false

        for _, key in ipairs(sortedKeys) do
            if searchNeedle == "" or NormalizeDropdownSearchText(key):find(searchNeedle, 1, true) then
                local path = list[key]
                hasMatch = true
                rootDescription:CreateRadio(key, function() return self._selectedValue == key end, function()
                    self._selectedValue = key
                    SetDropdownDisplayText(self, key)
                    if self._onSelect then self._onSelect(key, path) end
                end)
            end
        end

        if not hasMatch then
            rootDescription:CreateTitle(L["无匹配结果"])
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
        dropdown.labelText = EXUI:CreateVisualFontString(dropdown, EXFONTFRAME, "GameFontHighlight")
        dropdown.labelText:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 0, 2)
    end

    ApplyGridDropdownSize(dropdown, width)
    SyncDropdownMenuLayer(dropdown, parent)
    if dropdown.EnableMouse then
        dropdown:EnableMouse(true)
    end
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
        if self._externalSearchEnabled then AddSearchSpacer(rootDescription) else rootDescription:CreateTitle(L["选择材质"]) end
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
            end
        end

        if not hasMatch then
            rootDescription:CreateTitle(L["无匹配结果"])
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
        dropdown.labelText = EXUI:CreateVisualFontString(dropdown, EXFONTFRAME, "GameFontHighlight")
        dropdown.labelText:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 0, 2)
    end
    ApplyGridDropdownSize(dropdown, width)
    SyncDropdownMenuLayer(dropdown, parent)
    if dropdown.EnableMouse then
        dropdown:EnableMouse(true)
    end

    -- [池化关键] 将状态挂到 self，避免每次 Render 生成新闭包链
    dropdown._selectedValue = type(currentValue) == "string" and currentValue or LSM:GetDefault("sound")
    dropdown._onSelect = onSelect
    -- GridLSMDropdown 可被字体、材质等页面复用；借用时必须重置标题字体，
    -- 否则会把上一页的字号带到音效组。
    if dropdown.labelText and dropdown.labelText.SetFontObject then
        dropdown.labelText:SetFontObject(GameFontHighlight)
    end
    dropdown.labelText:SetText(label or "")
    SetDropdownSearchEnabled(dropdown, searchConfig)

    SetDropdownDisplayText(dropdown, dropdown._selectedValue or "None")

    dropdown:SetupMenu(function(self, rootDescription)
        if self._externalSearchEnabled then AddSearchSpacer(rootDescription) else rootDescription:CreateTitle(L["选择音效"]) end
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
            rootDescription:CreateTitle(L["无匹配结果"])
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
                local playBtn = MenuTemplates.AttachBasicButton(button, 16, 16)
                playBtn:SetPoint("RIGHT", -5, 0)
                local tex = playBtn:AttachTexture()
                tex:SetAllPoints()
                tex:SetTexture("Interface\\Common\\VoiceChat-Speaker")
                tex:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- [标准内裁剪]
                tex:SetVertexColor(0.8, 0.8, 0.8)
                playBtn:SetScript("OnEnter", function(self) tex:SetVertexColor(1, 1, 1) end)
                playBtn:SetScript("OnLeave", function(self) tex:SetVertexColor(0.8, 0.8, 0.8) end)
                MenuTemplates.SetUtilityButtonClickHandler(playBtn, function()
                    if path then PlaySoundFile(path, "Master") end
                end)
            end)
        end

        if #exKeys > 0 then
            local submenu = rootDescription:CreateButton(L["EXWIND音效"])
            for _, key in ipairs(exKeys) do
                AddSoundToMenu(submenu, key, list[key])
            end
            if #otherKeys > 0 then
                rootDescription:CreateDivider()
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
        dropdown.labelText = EXUI:CreateVisualFontString(dropdown, EXFONTFRAME, "GameFontHighlight")
        dropdown.labelText:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 0, 2)
    end

    ApplyGridDropdownSize(dropdown, width)
    SyncDropdownMenuLayer(dropdown, parent)
    if dropdown.EnableMouse then
        dropdown:EnableMouse(true)
    end
    dropdown.labelText:SetText(label or "")

    -- [v4.3.2] 将状态挂载到 Self，防止闭包泄漏
    dropdown._options = options
    dropdown._selections = selections
    dropdown._onUpdate = onUpdate
    SetDropdownSearchEnabled(dropdown, searchConfig)

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
        if #selectedLabels > 0 then
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
        rootDescription:SetScrollMode(400)
        if self._externalSearchEnabled then AddSearchSpacer(rootDescription) else rootDescription:CreateTitle(label) end

        if not self._options then return end

        local searchNeedle = NormalizeDropdownSearchText(self._searchText)
        local hasMatch = false
        for _, option in ipairs(self._options) do
            local optionLabel = GetOptionLabel(option)
            local optionValue = GetOptionValue(option)
            if searchNeedle == "" or NormalizeDropdownSearchText(optionLabel):find(searchNeedle, 1, true) then
                hasMatch = true
                rootDescription:CreateCheckbox(optionLabel,
                    function() return self._selections[optionValue] == true end,
                    function()
                        self._selections[optionValue] = not self._selections[optionValue]
                        self:RefreshSelectionDisplay()
                        return MenuResponse.Refresh
                    end
                )
            end
        end

        if not hasMatch then
            rootDescription:CreateTitle(L["无匹配结果"])
        end
        rootDescription:CreateDivider()
        rootDescription:CreateButton(L["清空全部"], function()
            for k in pairs(self._selections) do self._selections[k] = nil end
            self:RefreshSelectionDisplay()
            return MenuResponse.Refresh
        end)
    end)

    -- 兼容旧接口
    dropdown.dropdown = dropdown

    return dropdown
end

-- =========================================================
-- 5. 通用按钮 (Button) - [v4.3.1] 支持池化
-- =========================================================
function EXUI:CreateButton(parent, width, height, text, onClick)
    local EXFactory = _G.ExwindFactory
    local btn

    if EXFactory then
        -- 从池获取
        btn = self:AcquireControl("GridButton", parent)
        -- 清理旧的 OnClick
        btn:SetScript("OnClick", nil)
        btn:SetScript("PreClick", nil)
        btn:SetScript("PostClick", nil)
        btn:SetScript("OnMouseDown", nil)
        btn:SetScript("OnMouseUp", nil)
    else
        -- 兜底
        btn = CreateFrame("Button", nil, parent, "SharedButtonLargeTemplate")
    end

    btn:SetSize(width or 120, height or 32)
    if btn.EnableMouse then
        btn:EnableMouse(true)
    end
    if btn.Enable then
        btn:Enable()
    end
    if btn.RegisterForClicks then
        btn:RegisterForClicks("LeftButtonUp")
    end

    -- 统一切换到暴雪 tertiary 按钮材质，仅改视觉不改交互逻辑。
    if btn.SetNormalAtlas then
        btn:SetNormalAtlas("common-button-tertiary-normal")
    end
    if btn.SetPushedAtlas then
        btn:SetPushedAtlas("common-button-tertiary-pressed")
    end
    if btn.SetDisabledAtlas then
        btn:SetDisabledAtlas("common-button-tertiary-disabled")
    end
    if btn.SetHighlightAtlas then
        btn:SetHighlightAtlas("common-button-tertiary-normal", "ADD")
    end

    btn:SetText(text)

    if onClick then
        btn:SetScript("OnClick", onClick)
    end

    return btn
end

-- =========================================================
-- 5b. 图片按钮 (PicButton) - 支持 Normal/Pushed/Highlight 贴图
-- =========================================================
function EXUI:CreatePicButton(parent, width, height, normalTex, pushedTex, highlightTex, onClick, noCrop)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width or 32, height or 32)

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
        -- 自动生成按下效果：稍微缩小并位移
        btn:SetPushedTextOffset(1, -1)
        if btn.Normal then
            -- 如果没有 Pushed 贴图，按下时给 Normal 加点暗色滤镜
            btn:GetPushedTexture():SetVertexColor(0.7, 0.7, 0.7)
        end
    end

    -- 3. 高亮(滑过)状态贴图
    if highlightTex then
        local h = EXUI:CreateVisualTexture(btn, EXEDITORFRAME)
        h:SetTexture(highlightTex)
        h:SetAllPoints()
        h:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        btn:SetHighlightTexture(h)
    else
        -- 自动生成高亮效果：半透明白光
        local h = EXUI:CreateVisualTexture(btn, EXEDITORFRAME)
        h:SetTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
        h:SetAllPoints()
        h:SetBlendMode("ADD")
        btn:SetHighlightTexture(h)
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
        container:SetSize(200, 28)

        local cb = CreateFrame("CheckButton", nil, container, "MinimalCheckboxTemplate")
        cb:SetSize(28, 28)
        cb:SetPoint("LEFT", container, "LEFT", 0, 0)
        -- 移除旧版硬编码贴图，使用模板自带的现代 Atlas
        container.checkbox = cb

        local label = EXUI:CreateVisualFontString(container, EXFONTFRAME, "GameFontHighlight")
        label:SetPoint("LEFT", cb, "RIGHT", 6, 0)
        container.label = label

        function container:SetChecked(v) self.checkbox:SetChecked(v) end

        function container:GetChecked() return self.checkbox:GetChecked() end
    end

    -- 设置当前值
    container:SetSize(200, 28)
    container.checkbox:SetChecked(initialValue)
    container.label:SetText(text or "")
    if container.EnableMouse then
        container:EnableMouse(false)
    end
    container:SetScript("OnEnter", nil)
    container:SetScript("OnLeave", nil)
    if container.checkbox.EnableMouse then
        container.checkbox:EnableMouse(true)
    end
    container.checkbox:SetScript("OnEnter", nil)
    container.checkbox:SetScript("OnLeave", nil)
    container.checkbox:SetScript("PreClick", nil)
    container.checkbox:SetScript("PostClick", nil)

    -- 设置回调
    container.checkbox:SetScript("OnClick", function(self)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        if onClick then onClick(self:GetChecked() == true) end
    end)

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
    end

    -- 每个数值控件的视觉顺序固定为：标题 → 全宽轨道 → 数字输入框。
    -- 输入框是 slider 的子项，绝不再锚外层 Group 或额外的 control root。
    -- width 始终表示轨道本体的完整宽度。
    local controlWidth = tonumber(width) or 200
    local numberInputWidth = 42
    slider:SetWidth(controlWidth)

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

    -- [池化关键] 将回调存到 slider 属性。第九参数接受 table，能穿过
    -- ElvUI 对 CreateSlider 的旧签名包装；第十参数是原生路径的可选别名。
    local lifecycle = type(onValueChanged) == "table" and onValueChanged
        or (type(callbacks) == "table" and callbacks)
        or nil
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
        slider.ValueText = EXUI:CreateVisualFontString(slider, EXFONTFRAME, "GameFontNormal")
        slider.ValueText:SetFontObject("GameFontNormal")
        slider.ValueText:SetPoint("BOTTOMRIGHT", slider, "TOPRIGHT", -2, 1)
        slider.ValueText:SetJustifyH("RIGHT")
    end
    if not slider.Title then
        slider.Title = EXUI:CreateVisualFontString(slider, EXFONTFRAME, "GameFontNormal")
        slider.Title:SetFontObject("GameFontNormal")
        slider.Title:SetPoint("BOTTOMLEFT", slider, "TOPLEFT", 0, 1)
        slider.Title:SetJustifyH("LEFT")
        slider.Title:SetWordWrap(false)
    end
    slider.Title:ClearAllPoints()
    slider.Title:SetPoint("BOTTOMLEFT", slider, "TOPLEFT", 0, 1)
    slider.Title:SetPoint("BOTTOMRIGHT", slider, "TOPRIGHT", 0, 1)
    slider.Title:SetJustifyH("CENTER")
    slider.labelText = slider.Title

    -- 保留 ValueText 属性给旧皮肤/旧样式代码，但正式可编辑数值由 numberInput 显示。
    slider.ValueText:Hide()

    if not slider.numberInput then
        local input = CreateFrame("EditBox", nil, slider, "BackdropTemplate")
        input:SetAutoFocus(false)
        input:SetFontObject("GameFontHighlightSmall")
        input:SetJustifyH("CENTER")
        input:SetTextInsets(4, 4, 0, 0)
        input:SetBackdrop(EXUI.TooltipBackdrop)
        input:SetBackdropColor(0, 0, 0, 0.55)
        input:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.85)
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
    numberInput:ClearAllPoints()
    -- 数字输入框固定在轨道正下方的中线；轨道保持完整可用宽度。
    numberInput:SetPoint("TOP", slider, "BOTTOM", 0, 1)
    numberInput:SetSize(numberInputWidth, 16)
    numberInput:Show()

    -- 标题固定居中于轨道正上方，不为输入框预留右侧空间。
    slider.Title:ClearAllPoints()
    slider.Title:SetPoint("BOTTOMLEFT", slider, "TOPLEFT", 0, 1)
    slider.Title:SetPoint("BOTTOMRIGHT", slider, "TOPRIGHT", 0, 1)
    slider.Title:SetJustifyH("CENTER")

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

            -- 模板/stepper 可以给出带浮点尾巴的值；只让标准化后的值进入 DB。
            if math.abs(normalized - value) > 0.000001 then
                if not s._exNormalizing then
                    s._exNormalizing = true
                    s:SetValue(normalized)
                    s._exNormalizing = false
                end
                return
            end

            UpdateDisplayedValue(s, normalized)
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

        -- Blizzard 的左右 Stepper 直接修改 inner Slider。这个变化会正常触发
        -- OnValueChanged（因此旧 onValueChanged 调用者保持原状），但它不是轨道
        -- 拖动，_exDragging 不会设为 true；仅使用 onLive/onCommit 的新 Grid 字段
        -- 因而会出现“数字变了、预览不变”。在原生 OnClick 完成后，以最终 inner
        -- value 走一次同一条 commit 入口即可：不新建渲染路径、不补发 live，也不
        -- 影响程序化 SetValue/silent 回填。
        local function CommitStepperClick()
            if slider._exDragging then return end
            slider:SetEXUIValue(GetInnerValue(slider), "commit")
        end
        if slider.Back then slider.Back:HookScript("OnClick", CommitStepperClick) end
        if slider.Forward then slider.Forward:HookScript("OnClick", CommitStepperClick) end
        slider._sliderInit = true
    end

    -- 输入框仅在回车/失焦时提交，输入过程中绝不触发页面全量刷新。
    numberInput:SetScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(0.2, 0.85, 0.6, 1)
    end)
    numberInput:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.85)
        if self._exSkipLostCommit then
            self._exSkipLostCommit = nil
            return
        end
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

    return slider
end

-- =========================================================
-- 8. 通用分隔线 (Separator)
-- =========================================================
function EXUI:CreateSeparator(parent, width)
    local line = EXUI:CreateVisualTexture(parent, EXBASEFRAME)
    -- 分隔线必须是一个真实物理像素；UI 缩放下逻辑单位 1 不等于屏幕 1px。
    -- Grid 会在最终布局与 scale 变化时再次重套，非 Grid 调用也在首次创建时正确。
    local PixelUtil = _G.PixelUtil
    if PixelUtil and PixelUtil.SetSize then
        PixelUtil.SetSize(line, width or 200, 1, 1, 1)
    else
        line:SetSize(width or 200, 1)
    end
    line:SetTexture("Interface\\Buttons\\WHITE8X8")
    -- 使用渐变效果，让线看起来更高级
    line:SetGradient("HORIZONTAL", CreateColor(1, 1, 1, 0.3), CreateColor(1, 1, 1, 0.05))
    return line
end

-- =========================================================
-- 9. 分段标题 (Header with Line) - [v4.3.1] 支持池化
-- =========================================================
function EXUI:CreateHeader(parent, text, width)
    local EXFactory = _G.ExwindFactory
    local container

    if EXFactory then
        -- 从池获取（池中已预创建 Title 和 Line）
        container = self:AcquireControl("GridHeader", parent)
    else
        -- 兜底：传统创建
        container = CreateFrame("Frame", nil, parent)
        container:SetSize(width or 550, 40)

        local title = EXUI:CreateVisualFontString(container, EXFONTFRAME, "GameFontNormalHuge")
        title:SetPoint("TOPLEFT", 0, -5)
        title:SetTextColor(1, 0.82, 0)
        container.Title = title

        local line = EXUI:CreateVisualTexture(container, EXBASEFRAME)
        line:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
        line:SetPoint("RIGHT", 0, 0)
        local PixelUtil = _G.PixelUtil
        if PixelUtil and PixelUtil.SetHeight then
            PixelUtil.SetHeight(line, 1, 1)
        else
            line:SetHeight(1)
        end
        line:SetTexture("Interface\\Buttons\\WHITE8X8")
        line:SetGradient("HORIZONTAL", CreateColor(1, 1, 1, 0.5), CreateColor(1, 1, 1, 0.05))
        container.Line = line
    end

    container:SetSize(width or 550, 40)
    container.Title:SetText(text or "")

    return container
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
            txt:SetFontObject("GameFontHighlight")
            btn.labelText = txt
        end
    end

    -- 1. 主容器
    btn:SetSize(225, 36)
    if btn.EnableMouse then
        btn:EnableMouse(true)
    end

    -- 2. 设置 Tooltip 风格的背景与边框
    btn:SetBackdrop(EXUI.TooltipBackdrop)
    btn:SetBackdropColor(0.05, 0.05, 0.05, 0.8)
    btn:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.8)

    -- 3. 左侧预览色块
    local swatch = btn.swatch
    if swatch then
        swatch:ClearAllPoints()
        swatch:SetSize(16, 16)
        swatch:SetPoint("LEFT", btn, "LEFT", 10, 0)
        swatch:SetTexture("Interface\\Buttons\\WHITE8X8")
    end

    if not btn.swatchBorder then
        btn.swatchBorder = CreateFrame("Frame", nil, btn, "BackdropTemplate")
        btn.swatchBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    end
    btn.swatchBorder:ClearAllPoints()
    btn.swatchBorder:SetPoint("TOPLEFT", swatch, -1, 1)
    btn.swatchBorder:SetPoint("BOTTOMRIGHT", swatch, 1, -1)
    btn.swatchBorder:SetBackdropBorderColor(0, 0, 0, 0.8)

    -- 4. 文本标签
    if not btn.labelText then
        btn.labelText = btn.label
    end
    if not btn.labelText then
        btn.labelText = EXUI:CreateVisualFontString(btn, EXFONTFRAME)
        btn.labelText:SetFontObject("GameFontHighlight")
    end
    local text = btn.labelText
    text:SetFontObject("GameFontHighlight")
    text:ClearAllPoints()
    text:SetPoint("LEFT", swatch, "RIGHT", 10, 0)
    text:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
    text:SetJustifyH("LEFT")
    text:SetText(label or "")

    -- [关键] 属性挂载，以便池化复用时更新
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
            self:SetBackdropColor(r * 0.2, g * 0.2, b * 0.2, 0.75)
            self:SetBackdropBorderColor(r, g, b, 0.4)
        end
    end

    btn:UpdateColor()

    if not btn.FinishColorTransaction then
        function btn:FinishColorTransaction(token)
            local session = self._colorPickerSession
            if not session or (token ~= nil and session.token ~= token) then return false end
            self._colorPickerSession = nil
            session.transaction.onCommit(session.current)
            return true
        end
    end

    btn:SetScript("OnClick", function(self)
        local d, k = self._currentDb, self._currentKey
        if type(d) ~= "table" then return end

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
        local token
        if transaction then
            token = (self._colorPickerToken or 0) + 1
            self._colorPickerToken = token
            self._colorPickerSession = {
                token = token,
                transaction = transaction,
                original = { r = currR, g = currG, b = currB, a = currA },
                current = { r = currR, g = currG, b = currB, a = currA },
            }
            transaction.onBegin()
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
            local previousOwner, previousToken = ColorPickerFrame._exuiColorTransactionOwner, ColorPickerFrame._exuiColorTransactionToken
            if previousOwner and type(previousOwner.FinishColorTransaction) == "function" then
                previousOwner:FinishColorTransaction(previousToken)
            end
            ColorPickerFrame._exuiColorTransactionOwner, ColorPickerFrame._exuiColorTransactionToken = nil, nil
        end

        -- 打开 picker 只 Begin 一次；连续 swatch/opacity 回调只写 DB 并 Patch
        -- 当前 Panel。OnHide 才统一 Commit，取消会先恢复打开时的值再受控结束。
        local function ApplyColor(r, g, b, a)
            if transaction then
                local value = { r = r, g = g, b = b, a = a }
                transaction.onLive(value)
                local session = self._colorPickerSession
                if session and session.token == token then session.current = value end
            else
                SetDBColor(r, g, b, a)
                if self._currentOnUpdate then self._currentOnUpdate(d) end
            end
            self:UpdateColor()
        end

        local info = {
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                local a = self._hasAlpha and ColorPickerFrame:GetColorAlpha() or 1
                ApplyColor(r, g, b, a)
            end,
            opacityFunc = self._hasAlpha and function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                local a = ColorPickerFrame:GetColorAlpha()
                ApplyColor(r, g, b, a)
            end or nil,
            cancelFunc = function(prev)
                local session = self._colorPickerSession
                local original = session and session.original
                local r = (prev and prev.r) or (original and original.r) or currR
                local g = (prev and prev.g) or (original and original.g) or currG
                local b = (prev and prev.b) or (original and original.b) or currB
                local a = (prev and (prev.a or prev.opacity)) or (original and original.a) or currA
                ApplyColor(r, g, b, a)
                if transaction then self:FinishColorTransaction(token) end
            end,
            hasOpacity = self._hasAlpha,
            opacity = self._hasAlpha and currA or 1,
            r = currR,
            g = currG,
            b = currB,
        }
        ColorPickerFrame:SetupColorPickerAndShow(info)
        if transaction then
            ColorPickerFrame._exuiColorTransactionOwner = self
            ColorPickerFrame._exuiColorTransactionToken = token
        end
        PromoteColorPickerForOwner(self)
    end)
    return btn
end

-- =========================================================
-- 10.1 文字设置组（图标设置同款布局）
-- 纯文字样式：时间格式由独立 CreateTimeFormatGroup 负责。
-- =========================================================
-- 组合控件的子控件会常驻在宿主下面。代理把读写转发到“本次借用”的数据表，
-- 这样复用后的 Slider / Dropdown / ColorButton 不会继续引用上一条规则。
local function CompositePathValue(db, path)
    if path == nil or path == "" then return db end
    local value = db
    for part in string.gmatch(path, "[^%.]+") do
        value = type(value) == "table" and value[part] or nil
    end
    return value
end

local function CompositePathSet(db, path, value)
    if type(db) ~= "table" or type(path) ~= "string" or path == "" then return false end
    local target, last = db, nil
    for part in string.gmatch(path, "[^%.]+") do
        if last then
            target[last] = type(target[last]) == "table" and target[last] or {}
            target = target[last]
        end
        last = part
    end
    if not last then return false end
    target[last] = value
    return true
end

local function CreateCompositeProxy(host, path)
    return setmetatable({}, {
        __index = function(_, field)
            local target = CompositePathValue(host._exCompositeDb, path)
            return type(target) == "table" and target[field] or nil
        end,
        __newindex = function(_, field, value)
            local target = CompositePathValue(host._exCompositeDb, path)
            if type(target) == "table" then target[field] = value end
        end,
    })
end

local function AcquireCompositeGroup(poolType, parent)
    local factory = _G.ExwindFactory
    if factory and factory.AcquireCompositeHost then
        return factory:AcquireCompositeHost(poolType, parent)
    end
    return CreateFrame("Frame", nil, parent, "BackdropTemplate"), true
end

-- Composite hosts normally come from a BackdropTemplate pool.  A module can
-- nevertheless pass a pool key which was not registered yet; FramePool then
-- intentionally creates a plain Frame for that key.  A settings group is a
-- valid composite host in either case, so its visual shell must not assume the
-- optional Backdrop API exists.  This is an explicit rendering fallback (not a
-- protected-call suppression): it keeps the same background and one-pixel
-- outline using ordinary textures on a plain pooled Frame.
local function ApplyCompositeGroupSurface(host, bgR, bgG, bgB, bgA, borderR, borderG, borderB, borderA)
    if host.SetBackdrop and host.SetBackdropColor and host.SetBackdropBorderColor then
        host:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        host:SetBackdropColor(bgR, bgG, bgB, bgA)
        host:SetBackdropBorderColor(borderR, borderG, borderB, borderA)
        return
    end

    local surface = host._exCompositeFallbackSurface
    if not surface then
        surface = host:CreateTexture(nil, "BACKGROUND", nil, -8)
        surface:SetAllPoints(host)
        host._exCompositeFallbackSurface = surface

        local borders = {}
        local function CreateBorder(anchorA, relativeA, anchorB, relativeB)
            local border = host:CreateTexture(nil, "BORDER", nil, -8)
            border:SetPoint(anchorA, host, relativeA)
            border:SetPoint(anchorB, host, relativeB)
            borders[#borders + 1] = border
        end
        CreateBorder("TOPLEFT", "TOPLEFT", "TOPRIGHT", "TOPRIGHT")
        CreateBorder("BOTTOMLEFT", "BOTTOMLEFT", "BOTTOMRIGHT", "BOTTOMRIGHT")
        CreateBorder("TOPLEFT", "TOPLEFT", "BOTTOMLEFT", "BOTTOMLEFT")
        CreateBorder("TOPRIGHT", "TOPRIGHT", "BOTTOMRIGHT", "BOTTOMRIGHT")
        host._exCompositeFallbackBorders = borders
    end

    surface:SetColorTexture(bgR, bgG, bgB, bgA)
    surface:Show()
    for _, border in ipairs(host._exCompositeFallbackBorders or {}) do
        border:SetColorTexture(borderR, borderG, borderB, borderA)
        border:Show()
    end
    local borders = host._exCompositeFallbackBorders
    if borders then
        borders[1]:SetHeight(1)
        borders[2]:SetHeight(1)
        borders[3]:SetWidth(1)
        borders[4]:SetWidth(1)
    end
end

-- 右侧弹出面板不能作为 ScrollChild 的子对象：即使设为高层也会被滚动区域裁切。
-- 统一挂在 UIParent 的 DIALOG 层。内部 Dropdown 的列表由 Blizzard_Menu 自动创建在
-- FULLSCREEN_DIALOG，层级天然高于弹窗本身，避免同 TOOLTIP 层互相遮挡。
-- CompositeFontGroup / IconGroup / TimerBarGroup 都从这里取得弹层；层级恢复
-- 必须是这一处的统一职责，不能由各组的右侧按钮各自补丁。
local function RaiseCompositePopupHost(popup)
    if not popup then return end
    popup:SetFrameStrata("DIALOG")
    popup:SetFrameLevel(math.max(1000, (UIParent:GetFrameLevel() or 1) + 1000))
    if popup.SetToplevel then popup:SetToplevel(true) end
    -- 同 strata 的浮层会随着点击顺序而重叠；空白区点击也必须把当前 popup
    -- 放回最前，不能让它落到设置主框或另一张已存在 popup 后面。
    if popup.Raise then popup:Raise() end
end

local function CreateCompositePopupHost(owner, width, height)
    local popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    if EXUI.SetControlAppearance then
        EXUI:SetControlAppearance(popup, EXUI:GetControlAppearance(owner))
    end
    popup:SetSize(width, height)
    -- 主面板和它的 ModalLayer 同样在 DIALOG；弹窗必须明显高于二者，
    -- 而其下拉列表再由 FULLSCREEN_DIALOG 覆盖。
    RaiseCompositePopupHost(popup)
    popup:HookScript("OnShow", RaiseCompositePopupHost)
    popup:HookScript("OnMouseDown", RaiseCompositePopupHost)
    popup._exPopupOwner = owner
    return popup
end

-- Composite 控件除自身字段外，允许以纯数据声明“同一 DB、同一次 commit”必须
-- 一并写入的字段。它不是回调、也不保存模块函数；标准 Slider binder 只消费
-- 这份公开元数据，因而接管生命周期后不会丢失控件固有语义。
local function ValidateCompositeCommitWritesMetadata(metadata)
    if metadata == nil then return nil end
    if type(metadata) ~= "table" then
        error("composite control metadata must be table", 3)
    end
    for key in pairs(metadata) do
        if key ~= "commitWrites" then
            error("composite control metadata only supports commitWrites", 3)
        end
    end
    if type(metadata.commitWrites) ~= "table" or #metadata.commitWrites == 0 then
        error("composite control commitWrites must be a non-empty array", 3)
    end
    for index, write in ipairs(metadata.commitWrites) do
        if type(write) ~= "table" or type(write.path) ~= "string" or write.path == "" then
            error("composite control commitWrites entry requires path", 3)
        end
        for key in pairs(write) do
            if key ~= "path" and key ~= "value" then
                error("composite control commitWrites entry only supports path/value", 3)
            end
        end
        local valueType = type(write.value)
        if valueType ~= "boolean" and valueType ~= "number" and valueType ~= "string" then
            error("composite control commitWrites value must be scalar: " .. tostring(index), 3)
        end
    end
    return metadata.commitWrites
end

local function RegisterCompositeControl(host, control, path, kind, metadata)
    if not control then return control end
    local commitWrites = ValidateCompositeCommitWritesMetadata(metadata)
    host._exCompositeControls = host._exCompositeControls or {}
    host._exCompositeControls[#host._exCompositeControls + 1] = {
        control = control, path = path, kind = kind,
        -- 仅允许声明式 commitWrites；禁止把私有 callback 塞进控件 metadata。
        commitWrites = commitWrites,
    }
    return control
end

local function CompositeDropdownText(value, items)
    for _, item in ipairs(items or {}) do
        if type(item) == "table" then
            if item.isMenu then
                local text = CompositeDropdownText(value, item.menu)
                if text then return text end
            elseif item[2] == value or tostring(item[2]) == tostring(value) then
                return item[1]
            end
        elseif item == value or tostring(item) == tostring(value) then
            return item
        end
    end
    return nil
end

local function RefreshCompositeControl(entry, db)
    local control, value = entry.control, CompositePathValue(db, entry.path)
    if not control then return end
    if entry.kind == "color" then
        -- 颜色按钮保存的是嵌套目标表引用。组合组从对象池复用时，必须像其它
        -- 控件一样重绑到本轮 DB；仅 UpdateColor 会继续写入上一次页面的表。
        local colorDB, colorKey = db, entry.path
        local parentPath, directKey = tostring(entry.path or ""):match("^(.*)%.([^%.]+)$")
        if parentPath and directKey then
            for part in string.gmatch(parentPath, "[^%.]+") do
                colorDB = type(colorDB) == "table" and colorDB[part] or nil
            end
            colorKey = directKey
        end
        if type(colorDB) == "table" then
            control._currentDb = colorDB
            control._currentKey = colorKey
        end
        if control.UpdateColor then control:UpdateColor() end
    elseif entry.kind == "check" then
        if control.SetChecked then control:SetChecked(value == true) end
    elseif entry.kind == "slider" then
        local callback = control._onValueChanged
        control._onValueChanged = nil
        if control.Init and control._exCompositeMin ~= nil then
            control:Init(tonumber(value) or control._exCompositeMin, control._exCompositeMin,
                control._exCompositeMax, control._exCompositeSteps)
        elseif control.SetValue then
            control:SetValue(tonumber(value) or 0)
        end
        control._onValueChanged = callback
        if control.ValueText and control._formatter then
            control.ValueText:SetText(control._formatter(tonumber(value) or 0))
        end
    elseif entry.kind == "dropdown" then
        if control._mediaType then
            control._selectedValue = value
            SetDropdownDisplayText(control, value or L["请选择..."])
        else
            control._currentValue = value
            SetDropdownDisplayText(control, CompositeDropdownText(value, control._items) or L["请选择..."])
        end
    elseif entry.kind == "edit" then
        if control.SetText then control:SetText(tostring(value or "")) end
    end
end

local function BindCompositeGroup(host, db, onUpdate, opts)
    host._exCompositeDb = db
    host._exCompositeOnUpdate = onUpdate
    host._exCompositeOpts = opts or {}
    for _, entry in ipairs(host._exCompositeControls or {}) do
        RefreshCompositeControl(entry, db)
    end
    if host._exCompositeTitle and host._exCompositeLabel then
        host._exCompositeTitle:SetText(host._exCompositeLabel)
    end
    if type(host._exCompositeConfigure) == "function" then
        host:_exCompositeConfigure()
    end
end

-- Composite Host 会被 FramePool 交给不同宽度的 Grid 项目复用。仅 SetSize 会让
-- 内部卡片保留上一次借用时的绝对坐标/宽度，因此把“宿主尺寸 + 内部重排”收口。
-- 这里不保存视觉状态，也不触发配置回调；每一种 Composite 在创建时登记自己的
-- 窄布局函数，复用时只按当前实际宽高重新锚定已有控件。
local function ReflowCompositeGroup(host, width, height)
    host:SetSize(width, height)
    if type(host._exCompositeReflow) == "function" then
        host:_exCompositeReflow(width, height)
    end
end

-- 预览拖动会由模块直接写回同一份 ModuleDB；当前可见 Grid 不能等到重开页面
-- 才重新绑定。组合控件统一从自己已绑定的 DB 回读，避免每个模块分别触碰
-- Slider / Dropdown / Checkbox 私有实现，也不引入第二张预览配置表。
function EXUI:RefreshCompositeGroupFromDB(host)
    if type(host) ~= "table" or type(host._exCompositeDb) ~= "table" then return false end
    BindCompositeGroup(host, host._exCompositeDb, host._exCompositeOnUpdate, host._exCompositeOpts)
    return true
end

local function AttachCompositeRelease(host)
    local factory = _G.ExwindFactory
    -- FramePool 在每次 Release 后都会清空 frame._exPoolRelease；因此组合宿主
    -- 每次 Acquire/重绑都必须重新登记本轮清理，不能用永久 attached 标记跳过。
    if not factory or not factory.AttachPoolRelease then return end
    factory:AttachPoolRelease(host, function(frame)
        for _, popup in ipairs(frame._exCompositePopups or {}) do popup:Hide() end
        -- modulecommonsettings 的字段由模块动态声明；宿主归池时必须先归还
        -- 本轮借用的标准子控件，不能把上一模块的字段树带进下一模块。
        if frame._exClearModuleCommonEntries then
            frame:_exClearModuleCommonEntries()
        end
        frame._exCompositeDb = nil
        frame._exCompositeOnUpdate = nil
        frame._exCompositeOpts = nil
        frame._moduleCommonDb = nil
        frame._soundGroupKey = nil
        frame._soundState = nil
    end)
end

local function CompositeEmitUpdate(host)
    if host._exCompositeOnUpdate then host._exCompositeOnUpdate(host._exCompositeDb) end
end

function EXUI:CreateFontGroup(parent, width, label, db, onUpdate, opts)
    db = type(db) == "table" and db or {}
    opts = type(opts) == "table" and opts or {}
    local offsetMin = tonumber(opts.offsetMin) or -200
    local offsetMax = tonumber(opts.offsetMax) or 200
    local shadowOffsetMin = tonumber(opts.shadowOffsetMin) or -20
    local shadowOffsetMax = tonumber(opts.shadowOffsetMax) or 20

    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local defaultFont = (LSM and LSM.GetDefault and LSM:GetDefault("font")) or "Friz Quadrata TT"
    local defaults = {
        enabled = true,
        font = defaultFont,
        size = 14,
        r = 1, g = 1, b = 1, a = 1,
        outline = "OUTLINE",
        x = 0, y = 0,
        shadow = false,
        shadowX = 1, shadowY = -1,
        shadowColorR = 0, shadowColorG = 0, shadowColorB = 0, shadowColorA = 1,
        autoWidth = false,
        maxWidth = 0,
        fixedWidth = 200,
        justifyH = "LEFT", justifyV = "MIDDLE",
        gradientEnabled = false,
        gradientStart = 0, gradientLength = 0,
        -- drawLayer / drawSubLevel 是旧存档导入兼容字段：不再补默认值、
        -- 不再暴露设置控件，所有 FontString 统一由 EXFONTFRAME 接管。
        rotation = 0,
    }
    for field, value in pairs(defaults) do
        if db[field] == nil then db[field] = value end
    end
    local groupWidth, groupHeight = width or 750, 220
    local group, isNew = AcquireCompositeGroup("CompositeFontGroup", parent)
    group._exCompositeLabel = label or L["文字设置"]
    BindCompositeGroup(group, db, onUpdate, opts)
    if not isNew then
        if group._exSetUnboundedWidthControls then group:_exSetUnboundedWidthControls(opts) end
        AttachCompositeRelease(group)
        ReflowCompositeGroup(group, groupWidth, groupHeight)
        return group
    end
    local proxy = CreateCompositeProxy(group)
    db = proxy
    local palette = {
        panel = { 0.094, 0.094, 0.106, 1 },
        card = { 0.112, 0.112, 0.125, 1 },
        utility = { 0.106, 0.106, 0.118, 1 },
        border = { 1, 1, 1, 0.10 },
        borderSoft = { 1, 1, 1, 0.075 },
        text = { 0.96, 0.96, 0.97, 1 },
        value = { 0.204, 0.827, 0.599, 1 },
        accent = { 0.204, 0.827, 0.599, 1 },
    }
    local flatBackdrop = {
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    }

    -- FontGroup 的 metric card 在 ScrollFrame 内首次显示时，Backdrop 的 1 UI
    -- 单位边缘会被父级的有效缩放采样到半个物理像素，因而出现上/左边像“消失”的
    -- 假象。卡片保留原有 Backdrop 作为纯背景；边缘只由这四条卡片专用的、按卡片
    -- 自身 effective scale 计算的物理像素 Texture 绘制。它不参与任何内容布局。
    local function InstallMetricCardPhysicalOutline(card)
        local lines = {}
        for index = 1, 4 do
            local line = card:CreateTexture(nil, "BORDER", nil, 7)
            line:SetTexture("Interface\\Buttons\\WHITE8X8")
            line:SetColorTexture(unpack(palette.border))
            if line.SetSnapToPixelGrid then line:SetSnapToPixelGrid(true) end
            if line.SetTexelSnappingBias then line:SetTexelSnappingBias(0) end
            lines[index] = line
        end
        card._exMetricCardPhysicalOutline = lines

        local revision = 0
        local function Apply()
            local scale = card:GetEffectiveScale()
            scale = (type(scale) == "number" and scale > 0) and scale or 1
            local pixelUtil = _G.PixelUtil
            local pixel = (pixelUtil and pixelUtil.GetNearestPixelSize)
                and pixelUtil.GetNearestPixelSize(1, scale, 1)
                or (1 / scale)

            local function SetPixelPoint(region, point, relativePoint)
                region:ClearAllPoints()
                if pixelUtil and pixelUtil.SetPoint then
                    pixelUtil.SetPoint(region, point, card, relativePoint, 0, 0, 1, 1)
                else
                    region:SetPoint(point, card, relativePoint, 0, 0)
                end
            end

            SetPixelPoint(lines[1], "TOPLEFT", "TOPLEFT")
            if pixelUtil and pixelUtil.SetPoint then
                pixelUtil.SetPoint(lines[1], "TOPRIGHT", card, "TOPRIGHT", 0, 0, 1, 1)
            else
                lines[1]:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, 0)
            end
            lines[1]:SetHeight(pixel)

            SetPixelPoint(lines[2], "BOTTOMLEFT", "BOTTOMLEFT")
            if pixelUtil and pixelUtil.SetPoint then
                pixelUtil.SetPoint(lines[2], "BOTTOMRIGHT", card, "BOTTOMRIGHT", 0, 0, 1, 1)
            else
                lines[2]:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", 0, 0)
            end
            lines[2]:SetHeight(pixel)

            SetPixelPoint(lines[3], "TOPLEFT", "TOPLEFT")
            if pixelUtil and pixelUtil.SetPoint then
                pixelUtil.SetPoint(lines[3], "BOTTOMLEFT", card, "BOTTOMLEFT", 0, 0, 1, 1)
            else
                lines[3]:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 0, 0)
            end
            lines[3]:SetWidth(pixel)

            SetPixelPoint(lines[4], "TOPRIGHT", "TOPRIGHT")
            if pixelUtil and pixelUtil.SetPoint then
                pixelUtil.SetPoint(lines[4], "BOTTOMRIGHT", card, "BOTTOMRIGHT", 0, 0, 1, 1)
            else
                lines[4]:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", 0, 0)
            end
            lines[4]:SetWidth(pixel)
        end

        local function Stabilize()
            revision = revision + 1
            local current = revision
            Apply()
            -- 父级 ScrollChild/缩放在首次 Show 后才完全落定；只补两帧，不保留
            -- OnUpdate/Ticker。revision 同时让池化复用后的旧回调失效。
            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0, function()
                    if current ~= revision then return end
                    Apply()
                    _G.C_Timer.After(0, function()
                        if current == revision then Apply() end
                    end)
                end)
            end
        end

        card:HookScript("OnShow", Stabilize)
        card:HookScript("OnSizeChanged", Stabilize)
        card:RegisterEvent("UI_SCALE_CHANGED")
        card:RegisterEvent("DISPLAY_SIZE_CHANGED")
        card:SetScript("OnEvent", function(_, event)
            if event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
                Stabilize()
            end
        end)
        Stabilize()
    end

    local function EmitUpdate() CompositeEmitUpdate(group) end

    -- FontGroup 控件写入同一份 ModuleDB 后仅经统一通知重套既有表面。
    local function GetFontInputMetadata()
        local activeOpts = group._exCompositeOpts or {}
        local metadata = activeOpts._exWriteContext
        if metadata == nil then return nil end
        if type(metadata) ~= "table" or type(metadata.moduleKey) ~= "string" or metadata.moduleKey == "" then
            error("CreateFontGroup requires Grid write context", 2)
        end
        local prefix = metadata.pathPrefix or metadata.path
        if type(prefix) ~= "string" or prefix == "" then
            error("CreateFontGroup Grid write context requires pathPrefix", 2)
        end
        local commitAPI = EXUI.CommitModuleValue
        if type(commitAPI) ~= "function" then
            error("CreateFontGroup requires its Core commit API", 2)
        end
        return metadata.moduleKey, prefix
    end
    local function CommitFontValue(field, value, onWrite)
        local moduleKey, prefix = GetFontInputMetadata()
        local function Write(nextValue)
            db[field] = nextValue
            if onWrite then onWrite(nextValue) end
        end
        if moduleKey then
            local payload = {
                moduleKey = moduleKey, path = prefix .. "." .. field,
                readValue = function() return db[field] end, writeValue = Write,
            }
            return EXUI:CommitModuleValue(payload, value)
        end
        Write(value)
        EmitUpdate()
        return true
    end
    local function CreateFontColorTransaction(colorKey)
        local fields = colorKey == "shadowColor"
            and { "shadowColorR", "shadowColorG", "shadowColorB", "shadowColorA" }
            or { "r", "g", "b", "a" }
        return function()
            -- ColorButton 是池化对象；必须在每次打开色盘时读取本次页面的合同，
            -- 不能把首次创建它的模块 key / path 闭包带到后续页面。
            local moduleKey, prefix = GetFontInputMetadata()
            if not moduleKey then return nil end
            local payload = {
                moduleKey = moduleKey, path = prefix .. "." .. colorKey,
                readValue = function()
                    return { r = db[fields[1]], g = db[fields[2]], b = db[fields[3]], a = db[fields[4]] }
                end,
                writeValue = function(value)
                    db[fields[1]], db[fields[2]], db[fields[3]], db[fields[4]] = value.r, value.g, value.b, value.a
                end,
            }
            return EXUI:CreateModuleNotifyFlow(payload)
        end
    end
    local function SetFontValue(field, value, phase, onWrite)
        db[field] = value
        if onWrite then onWrite(value) end
        if phase ~= "live" then EmitUpdate() end
    end

    -- 旧 RegisterModuleLayout 的 FontGroup 可以声明 registry 生命周期。每次按下
    -- 都从当前 pooled group 的 opts 取合同，避免把上一个模块的 moduleKey/path
    -- 闭包带到本页面；拖动只写真实 DB 并 patch 已挂载 Panel，commit 才正式刷新。
    local function CreateFontPreviewLifecycle(field, onWrite)
        local activeOpts = group._exCompositeOpts or {}
        local transaction = activeOpts._exWriteContext
        if transaction ~= nil then
            if type(transaction) ~= "table" or type(transaction.moduleKey) ~= "string" or transaction.moduleKey == "" then
                error("CreateFontGroup requires Grid write context", 2)
            end
            local prefix = transaction.pathPrefix or transaction.path
            if type(prefix) ~= "string" or prefix == "" then
                error("CreateFontGroup Grid write context requires pathPrefix", 2)
            end
            local createAPI = EXUI.CreateModuleNotifyFlow
            if type(createAPI) ~= "function" then
                error("CreateFontGroup requires its Core transaction API", 2)
            end
            local function Write(value)
                db[field] = value
                if onWrite then onWrite(value) end
            end
            local payload = {
                moduleKey = transaction.moduleKey,
                path = prefix .. "." .. field,
                readValue = function() return db[field] end,
                writeValue = Write,
            }
            return createAPI(EXUI, payload)
        end
        local metadata = activeOpts._exWriteContext
        if metadata == nil then return nil end
        if type(metadata) ~= "table" or type(metadata.moduleKey) ~= "string" or metadata.moduleKey == "" then
            error("CreateFontGroup requires Grid write context", 2)
        end
        local prefix = metadata.pathPrefix or metadata.path
        if type(prefix) ~= "string" or prefix == "" then
            error("CreateFontGroup Grid write context requires pathPrefix", 2)
        end
        if type(EXUI.CreateModuleNotifyFlow) ~= "function" then
            error("CreateFontGroup requires CreateModuleNotifyFlow", 2)
        end
        local function Write(value)
            db[field] = value
            if onWrite then onWrite(value) end
        end
        return EXUI:CreateModuleNotifyFlow({
            moduleKey = metadata.moduleKey,
            path = prefix .. "." .. field,
            readValue = function() return db[field] end,
            writeValue = Write,
            commit = function(value)
                Write(value)
                EmitUpdate()
            end,
        })
    end

    local function CreateFontSlider(host, sliderWidth, titleText, field, minValue, maxValue, value, stepValue, onWrite)
        local lifecycle
        local slider = self:CreateSlider(host, sliderWidth, titleText, minValue, maxValue, value, stepValue, nil, {
            onBegin = function()
                lifecycle = CreateFontPreviewLifecycle(field, onWrite)
                if lifecycle and lifecycle.onBegin then lifecycle.onBegin() end
            end,
            onLive = function(v)
                if lifecycle and lifecycle.onLive then lifecycle.onLive(v) else SetFontValue(field, v, "live", onWrite) end
            end,
            onCommit = function(v)
                -- 输入框不会触发原生轨道的 OnMouseDown；标准模块仍必须在这里
                -- 输入框同样读取当前 Grid 写入上下文。
                local inputOpts = group._exCompositeOpts or {}
                if not lifecycle and inputOpts._exWriteContext ~= nil then
                    lifecycle = CreateFontPreviewLifecycle(field, onWrite)
                end
                if lifecycle and lifecycle.onCommit then
                    lifecycle.onCommit(v)
                    lifecycle = nil
                else
                    SetFontValue(field, v, "commit", onWrite)
                end
            end,
        })
        return slider
    end
    local function StyleCheckbox(checkbox)
        checkbox.label:SetTextColor(unpack(palette.text))
        if checkbox.checkbox:GetCheckedTexture() then
            checkbox.checkbox:GetCheckedTexture():SetVertexColor(unpack(palette.accent))
        end
    end
    local function StyleSlider(slider)
        if slider.labelText then slider.labelText:SetTextColor(unpack(palette.text)) end
        if slider.ValueText then slider.ValueText:SetTextColor(unpack(palette.value)) end
    end

    group:SetSize(groupWidth, groupHeight)
    group:SetBackdrop(flatBackdrop)
    group:SetBackdropColor(unpack(palette.panel))
    group:SetBackdropBorderColor(unpack(palette.borderSoft))

    local header = CreateFrame("Frame", nil, group)
    header:SetSize(groupWidth, 40)
    header:SetPoint("TOPLEFT")
    local title = EXUI:CreateVisualFontString(header, EXFONTFRAME, "GameFontNormalHuge")
    title:SetPoint("LEFT", 15, 0)
    title:SetText(group._exCompositeLabel)
    title:SetTextColor(unpack(palette.text))
    group.labelText = title
    group._exCompositeTitle = title
    local titleAccent = EXUI:CreateVisualTexture(header, EXBASEFRAME)
    titleAccent:SetPoint("LEFT", 6, 0)
    titleAccent:SetSize(3, 21)
    titleAccent:SetColorTexture(unpack(palette.accent))

    local content = CreateFrame("Frame", nil, group)
    content:SetSize(groupWidth, groupHeight - 40)
    content:SetPoint("TOPLEFT", 0, -40)

    local padding, gap, controlsGap = 15, 12, 18
    local controlWidth = math.min(416, math.max(364, math.floor(groupWidth * 0.40)))
    local metricsWidth = groupWidth - padding * 2 - controlsGap - controlWidth
    local itemWidth = math.floor((metricsWidth - gap) / 2)
    local col1, col2 = padding, padding + itemWidth + gap
    -- 下拉框包含“标题 + 选择框”两层内容；卡片统一加高，
    -- 让三列卡片与右侧功能区的上下边界完整对齐。
    local row1, row2, row3 = -8, -76, -144
    local metricCardHeight = 60
    local controlX = padding + metricsWidth + controlsGap

    local function CreateMetricCard(x, y)
        local card = CreateFrame("Frame", nil, content, "BackdropTemplate")
        card:SetPoint("TOPLEFT", x, y)
        card:SetSize(itemWidth, metricCardHeight)
        card:SetBackdrop(flatBackdrop)
        card:SetBackdropColor(unpack(palette.card))
        -- Backdrop 不再画边，避免它与物理像素四边叠加/采样不一致。
        card:SetBackdropBorderColor(0, 0, 0, 0)
        InstallMetricCardPhysicalOutline(card)
        return card
    end

    -- 三行两列：颜色/大小、字体/X、描边/Y。
    local colorCard = CreateMetricCard(col1, row1)
    local sizeCard = CreateMetricCard(col2, row1)
    local fontCard = CreateMetricCard(col1, row2)
    local xCard = CreateMetricCard(col2, row2)
    local outlineCard = CreateMetricCard(col1, row3)
    local yCard = CreateMetricCard(col2, row3)
    local sliderWidth = itemWidth - 20

    -- 字体、颜色和描边属于日常选项，直接展示在主面板，不再藏进弹窗。
    local colorBtn = self:CreateColorButton(colorCard, L["文字颜色"], db, "", true, EmitUpdate,
        { _changeFlow = CreateFontColorTransaction("color") })
    colorBtn:SetPoint("TOPLEFT", 10, -8)

    local fontDrop = self:CreateLSMDropdown(fontCard, "font", sliderWidth, L["字体样式"], db.font, function(key)
        CommitFontValue("font", key)
    end)
    -- 下拉框的标签绘制在本体上方；下移本体以让标签留在同一张 52px 卡片内。
    fontDrop:SetPoint("TOPLEFT", 10, -26)

    local outlineItems = { { L["无"], "" }, { L["细"], "OUTLINE" }, { L["粗"], "THICKOUTLINE" }, { L["无锯齿"], "MONOCHROME" } }
    local outlineDrop = self:CreateDropdown(outlineCard, sliderWidth, L["文字描边"], outlineItems, db.outline, function(v)
        CommitFontValue("outline", v)
    end)
    outlineDrop:SetPoint("TOPLEFT", 10, -26)

    local sizeSlider = CreateFontSlider(sizeCard, sliderWidth, L["文字大小"], "size", 4, 100, db.size, 1)
    sizeSlider:SetPoint("TOPLEFT", 10, -20)

    local xSlider = CreateFontSlider(xCard, sliderWidth, L["X 轴偏移"], "x", offsetMin, offsetMax, db.x, 1)
    xSlider:SetPoint("TOPLEFT", 10, -20)

    local ySlider = CreateFontSlider(yCard, sliderWidth, L["Y 轴偏移"], "y", offsetMin, offsetMax, db.y, 1)
    ySlider:SetPoint("TOPLEFT", 10, -20)
    StyleSlider(sizeSlider)
    StyleSlider(xSlider)
    StyleSlider(ySlider)

    local controlCard = CreateFrame("Frame", nil, content, "BackdropTemplate")
    controlCard:SetPoint("TOPLEFT", controlX, row1)
    controlCard:SetSize(controlWidth, math.abs(row3 - row1) + metricCardHeight)
    controlCard:SetBackdrop(flatBackdrop)
    controlCard:SetBackdropColor(unpack(palette.utility))
    controlCard:SetBackdropBorderColor(1, 1, 1, 0.16)

    local showText = self:CreateCheckbox(controlCard, L["显示文字"], db.enabled, function(v)
        CommitFontValue("enabled", v)
    end)
    showText:SetPoint("TOPLEFT", 12, -4)
    showText:SetSize(156, 28)
    StyleCheckbox(showText)

    local shadowCheck = self:CreateCheckbox(controlCard, L["启用阴影"], db.shadow, function(v)
        CommitFontValue("shadow", v)
    end)
    shadowCheck:SetPoint("TOPLEFT", 12, -45)
    shadowCheck:SetSize(156, 28)
    StyleCheckbox(shadowCheck)

    local alignmentWidth = math.min(156, math.floor(controlWidth * 0.45))
    local justifyHItems = { { L["左对齐"], "LEFT" }, { L["居中"], "CENTER" }, { L["右对齐"], "RIGHT" } }
    local justifyH = self:CreateDropdown(controlCard, alignmentWidth, L["水平对齐"], justifyHItems, db.justifyH, function(v)
        CommitFontValue("justifyH", v)
    end)
    justifyH:SetPoint("TOPLEFT", 12, -100)

    local justifyVItems = { { L["顶部"], "TOP" }, { L["居中"], "MIDDLE" }, { L["底部"], "BOTTOM" } }
    local justifyV = self:CreateDropdown(controlCard, alignmentWidth, L["垂直对齐"], justifyVItems, db.justifyV, function(v)
        CommitFontValue("justifyV", v)
    end)
    justifyV:SetPoint("TOPLEFT", 12, -151)

    local gradientCheck = self:CreateCheckbox(controlCard, L["启用文字渐隐"], db.gradientEnabled, function(v)
        CommitFontValue("gradientEnabled", v)
    end)
    gradientCheck:SetPoint("TOPLEFT", 12, -127)
    gradientCheck:SetSize(176, 28)
    StyleCheckbox(gradientCheck)
    -- 当前文字 Region 没有可靠的跨版本渐隐/旋转实现；不把未消费字段暴露给用户。
    gradientCheck:Hide()

    local function CreatePopup(titleText, popupWidth, popupHeight)
        local popup = CreateCompositePopupHost(group, popupWidth, popupHeight)
        popup:SetBackdrop(flatBackdrop)
        popup:SetBackdropColor(unpack(palette.panel))
        popup:SetBackdropBorderColor(unpack(palette.border))
        popup:Hide()
        local popupTitle = EXUI:CreateVisualFontString(popup, EXFONTFRAME, "GameFontHighlight")
        popupTitle:SetPoint("TOPLEFT", 13, -9)
        popupTitle:SetText(titleText)
        popupTitle:SetTextColor(unpack(palette.text))
        local close = self:CreateButton(popup, 28, 24, "×", function() popup:Hide() end)
        close:SetPoint("TOPRIGHT", -7, -4)
        return popup
    end

    local popupScale = 1.3
    local popupWidth = math.floor(400 * popupScale)
    local shadowPopup = CreatePopup(L["阴影设置"], popupWidth, 140)
    local layoutPopup = CreatePopup(L["布局设置"], popupWidth, 156)
    local advancedPopup = CreatePopup(L["高级文字设置"], popupWidth, 210)
    local popupPad, popupGap = 14, 18
    local popupItemW = math.floor((popupWidth - popupPad * 2 - popupGap) / 2)
    local popupCol2 = popupPad + popupItemW + popupGap

    local shadowColor = self:CreateColorButton(shadowPopup, L["阴影颜色"], db, "shadowColor", true, EmitUpdate,
        { _changeFlow = CreateFontColorTransaction("shadowColor") })
    shadowColor:SetPoint("TOPLEFT", popupPad, -46)
    local shadowX = CreateFontSlider(shadowPopup, popupItemW, L["阴影 X 偏移"], "shadowX", shadowOffsetMin, shadowOffsetMax, db.shadowX, 0.1)
    shadowX:SetPoint("TOPLEFT", popupCol2, -42)
    local shadowY = CreateFontSlider(shadowPopup, popupItemW, L["阴影 Y 偏移"], "shadowY", shadowOffsetMin, shadowOffsetMax, db.shadowY, 0.1)
    shadowY:SetPoint("TOPLEFT", popupCol2, -95)
    StyleSlider(shadowX)
    StyleSlider(shadowY)

    local autoWidthCheck
    local fixedWidth = CreateFontSlider(layoutPopup, popupItemW, L["固定宽度"], "fixedWidth", 0, 1000, db.fixedWidth, 1, function()
        -- 用户调整固定宽度即明确选择固定宽度模式；数值 0 的语义是“按文字自身宽度”。
        -- 不自动关掉该模式会让滑条看似没有作用。
        db.autoWidth = false
        if autoWidthCheck.SetChecked then autoWidthCheck:SetChecked(false) end
    end)
    fixedWidth:SetPoint("TOPLEFT", popupPad, -42)
    local maxWidth = CreateFontSlider(layoutPopup, popupItemW, L["最大宽度 (0=不限)"], "maxWidth", 0, 1000, db.maxWidth, 1)
    maxWidth:SetPoint("TOPLEFT", popupCol2, -42)
    autoWidthCheck = self:CreateCheckbox(layoutPopup, L["自动宽度"], db.autoWidth, function(v)
        CommitFontValue("autoWidth", v)
    end)
    autoWidthCheck:SetPoint("TOPLEFT", popupPad, -96)
    autoWidthCheck:SetSize(156, 28)
    StyleCheckbox(autoWidthCheck)
    StyleSlider(fixedWidth)
    StyleSlider(maxWidth)

    local gradientStart = CreateFontSlider(advancedPopup, popupItemW, L["渐隐起点"], "gradientStart", 0, 1000, db.gradientStart, 1)
    gradientStart:SetPoint("TOPLEFT", popupPad, -42)
    local gradientLength = CreateFontSlider(advancedPopup, popupItemW, L["渐隐长度"], "gradientLength", 0, 1000, db.gradientLength, 1)
    gradientLength:SetPoint("TOPLEFT", popupCol2, -42)
    local rotation = CreateFontSlider(advancedPopup, popupItemW, L["文字旋转"], "rotation", -180, 180, db.rotation, 1)
    rotation:SetPoint("TOPLEFT", popupPad, -150)
    StyleSlider(gradientStart)
    StyleSlider(gradientLength)
    StyleSlider(rotation)

    local function TogglePopup(popup, anchor)
        local shouldShow = not popup:IsShown()
        shadowPopup:Hide()
        layoutPopup:Hide()
        advancedPopup:Hide()
        if shouldShow then
            popup:ClearAllPoints()
            popup:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -6)
            popup:Show()
        end
    end
    local function CreateUtilityButton(text, buttonWidth, onClick)
        local button = CreateFrame("Button", nil, controlCard, "BackdropTemplate")
        button:SetSize(buttonWidth, 28)
        button:RegisterForClicks("LeftButtonUp")
        button:SetBackdrop(flatBackdrop)
        button:SetBackdropColor(0.06, 0.15, 0.12, 0.72)
        button:SetBackdropBorderColor(0.204, 0.827, 0.599, 0.22)
        local textLabel = EXUI:CreateVisualFontString(button, EXFONTFRAME, "GameFontHighlightSmall")
        textLabel:SetPoint("CENTER", 0, -1)
        textLabel:SetText(text)
        textLabel:SetTextColor(unpack(palette.accent))
        button:SetScript("OnEnter", function()
            button:SetBackdropColor(0.07, 0.20, 0.15, 0.86)
            button:SetBackdropBorderColor(0.204, 0.827, 0.599, 0.58)
            textLabel:SetTextColor(0.75, 0.96, 0.86, 1)
        end)
        button:SetScript("OnLeave", function()
            button:SetBackdropColor(0.06, 0.15, 0.12, 0.72)
            button:SetBackdropBorderColor(0.204, 0.827, 0.599, 0.22)
            textLabel:SetTextColor(unpack(palette.accent))
        end)
        button:SetScript("OnClick", onClick)
        return button
    end

    local buttonWidth = math.min(187, math.floor(controlWidth * 0.45))
    local shadowButton = CreateUtilityButton(L["阴影设置"], buttonWidth, function(self) TogglePopup(shadowPopup, self) end)
    shadowButton:SetPoint("TOPRIGHT", controlCard, "TOPRIGHT", -10, -4)
    local layoutButton = CreateUtilityButton(L["布局设置"], buttonWidth, function(self) TogglePopup(layoutPopup, self) end)
    layoutButton:SetPoint("TOPRIGHT", controlCard, "TOPRIGHT", -10, -45)
    local advancedButton = CreateUtilityButton(L["高级设置"], buttonWidth, function(self) TogglePopup(advancedPopup, self) end)
    advancedButton:SetPoint("TOPRIGHT", controlCard, "TOPRIGHT", -10, -86)

    -- 单行公告等明确声明为无界文本的模块不能暴露会制造宽度限制的控件。
    -- 该组会被对象池复用，因而每次绑定都必须显式恢复/隐藏，不能把上一个
    -- 无界模块的可见性残留给普通文字模块。
    group._exFontAutoWidthCheck = autoWidthCheck
    group._exFontLayoutButton = layoutButton
    group._exSetUnboundedWidthControls = function(self, activeOpts)
        local unbounded = type(activeOpts) == "table" and activeOpts.unboundedWidth == true
        if self._exFontAutoWidthCheck then self._exFontAutoWidthCheck:SetShown(not unbounded) end
        if self._exFontLayoutButton then self._exFontLayoutButton:SetShown(not unbounded) end
    end
    group:_exSetUnboundedWidthControls(opts)

    group:HookScript("OnHide", function()
        shadowPopup:Hide()
        layoutPopup:Hide()
        advancedPopup:Hide()
    end)
    RegisterCompositeControl(group, colorBtn, "", "color")
    RegisterCompositeControl(group, fontDrop, "font", "dropdown")
    RegisterCompositeControl(group, outlineDrop, "outline", "dropdown")
    RegisterCompositeControl(group, sizeSlider, "size", "slider")
    RegisterCompositeControl(group, xSlider, "x", "slider")
    RegisterCompositeControl(group, ySlider, "y", "slider")
    RegisterCompositeControl(group, showText, "enabled", "check")
    RegisterCompositeControl(group, shadowCheck, "shadow", "check")
    RegisterCompositeControl(group, autoWidthCheck, "autoWidth", "check")
    RegisterCompositeControl(group, gradientCheck, "gradientEnabled", "check")
    RegisterCompositeControl(group, shadowColor, "shadowColor", "color")
    RegisterCompositeControl(group, shadowX, "shadowX", "slider")
    RegisterCompositeControl(group, shadowY, "shadowY", "slider")
    -- 固定宽度是 FontGroup 的公开控件语义：调整它必定切出自动宽度模式。
    -- 旧页面仍由上面的 Slider callback 保持此行为；标准生命周期接管时则
    -- 读取这份声明式 metadata，在同一 DB、同一次 commit 写入 autoWidth=false。
    RegisterCompositeControl(group, fixedWidth, "fixedWidth", "slider", {
        commitWrites = {
            { path = "autoWidth", value = false },
        },
    })
    RegisterCompositeControl(group, maxWidth, "maxWidth", "slider")
    RegisterCompositeControl(group, justifyH, "justifyH", "dropdown")
    RegisterCompositeControl(group, justifyV, "justifyV", "dropdown")
    RegisterCompositeControl(group, gradientStart, "gradientStart", "slider")
    RegisterCompositeControl(group, gradientLength, "gradientLength", "slider")
    RegisterCompositeControl(group, rotation, "rotation", "slider")
    group._exCompositePopups = { shadowPopup, layoutPopup, advancedPopup }
    group._fontGroupDb = proxy
    group._exCompositeReflow = function(self, nextWidth, nextHeight)
        local nextControlWidth = math.min(416, math.max(364, math.floor(nextWidth * 0.40)))
        local nextMetricsWidth = nextWidth - padding * 2 - controlsGap - nextControlWidth
        local nextItemWidth = math.floor((nextMetricsWidth - gap) / 2)
        local nextCol2 = padding + nextItemWidth + gap
        local nextControlX = padding + nextMetricsWidth + controlsGap
        local nextSliderWidth = nextItemWidth - 20

        header:SetSize(nextWidth, 40)
        content:SetSize(nextWidth, nextHeight - 40)
        for _, card in ipairs({ colorCard, fontCard, outlineCard }) do card:SetSize(nextItemWidth, metricCardHeight) end
        for _, card in ipairs({ sizeCard, xCard, yCard }) do card:SetSize(nextItemWidth, metricCardHeight) end
        colorCard:ClearAllPoints(); colorCard:SetPoint("TOPLEFT", content, "TOPLEFT", col1, row1)
        sizeCard:ClearAllPoints(); sizeCard:SetPoint("TOPLEFT", content, "TOPLEFT", nextCol2, row1)
        fontCard:ClearAllPoints(); fontCard:SetPoint("TOPLEFT", content, "TOPLEFT", col1, row2)
        xCard:ClearAllPoints(); xCard:SetPoint("TOPLEFT", content, "TOPLEFT", nextCol2, row2)
        outlineCard:ClearAllPoints(); outlineCard:SetPoint("TOPLEFT", content, "TOPLEFT", col1, row3)
        yCard:ClearAllPoints(); yCard:SetPoint("TOPLEFT", content, "TOPLEFT", nextCol2, row3)
        for _, slider in ipairs({ sizeSlider, xSlider, ySlider }) do slider:SetWidth(nextSliderWidth) end
        fontDrop:SetWidth(nextSliderWidth); outlineDrop:SetWidth(nextSliderWidth)
        colorBtn:SetWidth(nextSliderWidth)
        controlCard:ClearAllPoints(); controlCard:SetPoint("TOPLEFT", content, "TOPLEFT", nextControlX, row1)
        controlCard:SetSize(nextControlWidth, math.abs(row3 - row1) + metricCardHeight)
        local nextButtonWidth = math.min(187, math.floor(nextControlWidth * 0.45))
        local nextAlignmentWidth = math.min(156, math.floor(nextControlWidth * 0.45))
        justifyH:SetWidth(nextAlignmentWidth); justifyV:SetWidth(nextAlignmentWidth)
        shadowButton:SetWidth(nextButtonWidth); layoutButton:SetWidth(nextButtonWidth); advancedButton:SetWidth(nextButtonWidth)
    end
    group:_exCompositeReflow(groupWidth, groupHeight)
    -- 预览画布拖动会直接写入 db；提供统一回刷入口，让下方 X/Y 滑杆
    -- 立即同步，而不是下一次手动调整时从旧值跳回去。
    group.RefreshFromDB = function(self)
        BindCompositeGroup(self, self._exCompositeDb, self._exCompositeOnUpdate, self._exCompositeOpts)
    end
    AttachCompositeRelease(group)
    return group
end

-- =========================================================
-- 12. 音效设置复合组件 (Sound Settings Group)
-- 扁平前缀字段：<key>Enabled/Source/Label/LSM/Path/TtsText/Channel。
-- 来源集合由调用方 opts.sources 声明；未声明时绝不开放语音包。
-- =========================================================
local function ResolveSoundGroupSecondaryCheckbox(opts)
    local spec = type(opts) == "table" and opts.secondaryCheckbox or nil
    if spec == nil then return nil end
    if type(spec) ~= "table" then
        error("soundgroup secondaryCheckbox must be table", 3)
    end
    for field in pairs(spec) do
        if field ~= "key" and field ~= "label" then
            error("soundgroup secondaryCheckbox only supports key/label", 3)
        end
    end
    if type(spec.key) ~= "string" or spec.key == "" then
        error("soundgroup secondaryCheckbox requires non-empty key", 3)
    end
    if type(spec.label) ~= "string" or spec.label == "" then
        error("soundgroup secondaryCheckbox requires non-empty label", 3)
    end
    return spec
end

-- SoundGroup 的测量和控件重排必须共用同一份纯布局结果。额外复选框由组件
-- 自己占据第二行，因而能与“启用”使用完全相同的父级和水平内边距；未声明
-- secondaryCheckbox 的现有调用者仍保持原来的 104/180 高度。
function EXUI:BuildSoundGroupLayout(width, opts)
    local groupWidth = math.max(1, tonumber(width) or 750)
    local secondaryCheckbox = ResolveSoundGroupSecondaryCheckbox(opts)
    local extraHeight = secondaryCheckbox and 56 or 0
    if groupWidth >= 760 then
        return {
            height = 104 + extraHeight,
            isWide = true,
            secondaryCheckbox = secondaryCheckbox,
            enabledY = -4,
            secondaryY = -60,
            sourceY = -4,
            channelY = -4,
            testY = -4,
        }
    end
    return {
        height = 180 + extraHeight,
        isWide = false,
        secondaryCheckbox = secondaryCheckbox,
        enabledY = -8,
        secondaryY = -45,
        sourceY = -45 - extraHeight,
        channelY = -101 - extraHeight,
        testY = -104 - extraHeight,
    }
end

function EXUI:CreateSoundGroup(parent, width, label, db, key, onUpdate, opts)
    db = type(db) == "table" and db or {}
    opts = type(opts) == "table" and opts or {}
    key = tostring(key or "sound")

    local function HasUsablePackItems(items)
        if type(items) ~= "table" then return false end
        for _, item in ipairs(items) do
            if type(item) == "string" and item ~= "" then return true end
            if type(item) == "table" and item[1] ~= nil and item[2] ~= nil then return true end
        end
        return false
    end
    local function ResolveInitialPackItems()
        local packItems = opts.packItems
        if type(packItems) == "function" then
            local ok, result = pcall(packItems, db, key)
            packItems = ok and result or nil
        end
        return packItems
    end

    local allowed = {}
    local sources = {}
    local requestedSources = type(opts.sources) == "table" and opts.sources or { "lsm", "file", "tts" }
    local packAvailable = HasUsablePackItems(ResolveInitialPackItems())
    for _, source in ipairs(requestedSources) do
        if source == "pack" and not packAvailable then
            -- pack 没有本轮可用条目时不能成为可选来源，更不能被选为默认值。
        elseif (source == "pack" or source == "lsm" or source == "file" or source == "tts") and not allowed[source] then
            allowed[source] = true
            sources[#sources + 1] = source
        end
    end
    if #sources == 0 then
        sources = { "lsm", "file", "tts" }
        allowed = { lsm = true, file = true, tts = true }
    end

    local sourceItems = {
        pack = { L["语音包"], "pack" },
        lsm = { L["LSM音效"], "lsm" },
        file = { L["自定义路径"], "file" },
        tts = { L["TTS语音"], "tts" },
    }
    local dropdownSources = {}
    local defaultSource
    for _, source in ipairs(sources) do
        dropdownSources[#dropdownSources + 1] = sourceItems[source]
        if not defaultSource and source ~= "pack" then defaultSource = source end
    end
    defaultSource = defaultSource or sources[1]

    local group
    local suffix = {
        enabled = "Enabled", source = "Source", label = "Label", lsm = "LSM",
        path = "Path", tts = "TtsText", channel = "Channel",
    }
    local function Field(name) return ((group and group._soundGroupKey) or key) .. suffix[name] end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local defaultLSM = (LSM and LSM.GetDefault and LSM:GetDefault("sound")) or "None"
    local defaults = {
        enabled = false, source = defaultSource, label = "", lsm = defaultLSM,
        path = "", tts = "", channel = "Master",
    }
    for name, value in pairs(defaults) do
        local field = Field(name)
        if db[field] == nil then db[field] = value end
    end
    if not allowed[db[Field("source")]] then db[Field("source")] = defaultSource end

    -- 宽版标准页面统一使用一行：启用 / 来源 / 当前音效 / 输出 / 试听。
    -- 窄宿主仍保留两列，以免控件相互覆盖。
    local groupWidth = width or 750
    local soundLayout = self:BuildSoundGroupLayout(groupWidth, opts)
    local groupHeight = soundLayout.height
    local isNew
    group, isNew = AcquireCompositeGroup("CompositeSoundGroup", parent)
    group._exCompositeLabel = label or L["音效设置"]
    group._soundGroupKey = key
    group._soundState = {
        allowed = allowed, defaultSource = defaultSource, dropdownSources = dropdownSources,
        requestedSources = requestedSources,
    }
    BindCompositeGroup(group, db, onUpdate, opts)
    if not isNew then
        group:_exCompositeConfigure()
        AttachCompositeRelease(group)
        ReflowCompositeGroup(group, groupWidth, groupHeight)
        return group
    end

    local palette = {
        panel = { 0.094, 0.094, 0.106, 1 }, card = { 0.112, 0.112, 0.125, 1 },
        utility = { 0.106, 0.106, 0.118, 1 }, border = { 1, 1, 1, 0.10 },
        text = { 0.96, 0.96, 0.97, 1 }, value = { 0.204, 0.827, 0.599, 1 },
    }
    local flatBackdrop = {
        bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    }
    group:SetSize(groupWidth, groupHeight)
    group:SetBackdrop(flatBackdrop)
    group:SetBackdropColor(unpack(palette.panel))
    group:SetBackdropBorderColor(unpack(palette.border))

    local header = CreateFrame("Frame", nil, group)
    header:SetSize(groupWidth, 40); header:SetPoint("TOPLEFT")
    local title = EXUI:CreateVisualFontString(header, EXFONTFRAME, "GameFontNormalHuge")
    title:SetPoint("LEFT", 15, 0); title:SetText(group._exCompositeLabel); title:SetTextColor(unpack(palette.text))
    group.labelText, group._exCompositeTitle = title, title
    local accent = EXUI:CreateVisualTexture(header, EXBASEFRAME)
    accent:SetPoint("LEFT", 6, 0); accent:SetSize(3, 21); accent:SetColorTexture(unpack(palette.value))

    local content = CreateFrame("Frame", nil, group)
    content:SetPoint("TOPLEFT", 0, -40)
    -- 外层已经承担分组背景和标题；内容层不再额外套一张卡片框。
    local settingsCard = CreateFrame("Frame", nil, content)

    local function ActiveDB() return type(group._exCompositeDb) == "table" and group._exCompositeDb or nil end
    local function SetValue(name, value)
        local active = ActiveDB()
        if active then active[Field(name)] = value end
    end
    local function GetValue(name)
        local active = ActiveDB()
        return active and active[Field(name)] or defaults[name]
    end
    local function EmitUpdate() CompositeEmitUpdate(group) end

    local enabled = self:CreateCheckbox(settingsCard, L["启用"], GetValue("enabled"), function(value)
        SetValue("enabled", value); EmitUpdate()
    end)
    local secondaryCheckbox = self:CreateCheckbox(settingsCard, "", false, function(value)
        local activeOpts = group._exCompositeOpts or {}
        local spec = ResolveSoundGroupSecondaryCheckbox(activeOpts)
        local active = ActiveDB()
        if spec and active and CompositePathSet(active, spec.key, value) then
            EmitUpdate()
        end
    end)
    local sourceDrop = self:CreateDropdown(settingsCard, 200, L["音效来源"], dropdownSources, GetValue("source"), function(value)
        SetValue("source", value)
        group:_exCompositeConfigure()
        EmitUpdate()
    end)
    local packDrop = self:CreateDropdown(settingsCard, 200, L["语音包标签"], {}, GetValue("label"), function(value)
        SetValue("label", value); EmitUpdate()
    end)
    local lsmDrop = self:CreateLSMSoundDropdown(settingsCard, 200, L["选择音效 (LSM)"], GetValue("lsm"), function(value)
        SetValue("lsm", value); EmitUpdate()
    end)
    lsmDrop._mediaType = "sound"
    local pathInput = self:CreateEditBox(settingsCard, GetValue("path"), 200, 28, L["自定义路径"], {
        placeholder = L["示例: Interface\\AddOns\\MySound\\test.ogg"],
        onEnter = function(value) SetValue("path", value); EmitUpdate() end,
        onEditFocusLost = function(value) SetValue("path", value); EmitUpdate() end,
    })
    local ttsInput = self:CreateEditBox(settingsCard, GetValue("tts"), 200, 28, L["TTS文本"], {
        placeholder = L["输入要朗读的文字"],
        onEnter = function(value) SetValue("tts", value); EmitUpdate() end,
        onEditFocusLost = function(value) SetValue("tts", value); EmitUpdate() end,
    })
    local channels = {
        { L["主音量 (Master)"], "Master" }, { L["音效 (SFX)"], "SFX" },
        { L["环境 (Ambience)"], "Ambience" }, { L["音乐 (Music)"], "Music" },
        { L["对话 (Dialog)"], "Dialog" },
    }
    local channelDrop = self:CreateDropdown(settingsCard, 200, L["音频通道"], channels, GetValue("channel"), function(value)
        SetValue("channel", value); EmitUpdate()
    end)
    local testButton = self:CreateButton(settingsCard, 110, 28, opts.testLabel or L["试听"], function()
        local activeOpts = group._exCompositeOpts or {}
        if type(activeOpts.onTest) == "function" then
            activeOpts.onTest(group._exCompositeDb, group._soundGroupKey)
            return
        end
        -- Module declarations are pure data, so Grid soundgroup cannot carry a
        -- callback.  An explicit testButtonKey reuses the established module
        -- click-state contract; the module still owns the actual playback.
        local clickKey = activeOpts.testButtonKey
        local writeContext = activeOpts._exWriteContext
        if type(clickKey) == "string" and clickKey ~= ""
            and type(writeContext) == "table" and type(writeContext.moduleKey) == "string"
            and writeContext.moduleKey ~= "" then
            ExwindTools:UpdateState(writeContext.moduleKey .. ".ButtonClicked", {
                key = clickKey,
                fullPath = writeContext.pathPrefix,
                ts = GetTime(),
            })
        end
    end)

    enabled._soundField = "enabled"
    sourceDrop._soundField = "source"
    packDrop._soundField = "label"
    lsmDrop._soundField = "lsm"
    pathInput._soundField = "path"
    ttsInput._soundField = "tts"
    channelDrop._soundField = "channel"
    RegisterCompositeControl(group, enabled, Field("enabled"), "check")
    RegisterCompositeControl(group, sourceDrop, Field("source"), "dropdown")
    RegisterCompositeControl(group, packDrop, Field("label"), "dropdown")
    RegisterCompositeControl(group, lsmDrop, Field("lsm"), "dropdown")
    RegisterCompositeControl(group, pathInput, Field("path"), "edit")
    RegisterCompositeControl(group, ttsInput, Field("tts"), "edit")
    RegisterCompositeControl(group, channelDrop, Field("channel"), "dropdown")

    local function ResolvePackItems()
        local activeOpts = group._exCompositeOpts or {}
        local packItems = activeOpts.packItems
        if type(packItems) == "function" then
            local ok, result = pcall(packItems, group._exCompositeDb, group._soundGroupKey)
            packItems = ok and result or nil
        end
        return type(packItems) == "table" and packItems or {}
    end
    local function RebuildSourceState(state, packItems)
        local nextAllowed, nextItems, nextDefault = {}, {}, nil
        for _, candidate in ipairs(state.requestedSources or {}) do
            if candidate == "pack" and not HasUsablePackItems(packItems) then
                -- 动态 provider 本轮为空时，pack 必须从来源菜单消失。
            elseif (candidate == "pack" or candidate == "lsm" or candidate == "file" or candidate == "tts") and not nextAllowed[candidate] then
                nextAllowed[candidate] = true
                nextItems[#nextItems + 1] = sourceItems[candidate]
                if not nextDefault and candidate ~= "pack" then nextDefault = candidate end
            end
        end
        if #nextItems == 0 then
            nextAllowed = { lsm = true, file = true, tts = true }
            nextItems = { sourceItems.lsm, sourceItems.file, sourceItems.tts }
            nextDefault = "lsm"
        end
        state.allowed, state.dropdownSources, state.defaultSource = nextAllowed, nextItems, nextDefault or nextItems[1][2]
    end
    group._exCompositeConfigure = function(self)
        local state = self._soundState or {}
        local activeOpts = self._exCompositeOpts or {}
        local secondarySpec = ResolveSoundGroupSecondaryCheckbox(activeOpts)
        if testButton.SetText then testButton:SetText(activeOpts.testLabel or L["试听"]) end
        secondaryCheckbox:SetShown(secondarySpec ~= nil)
        if secondarySpec then
            secondaryCheckbox.label:SetText(secondarySpec.label)
            secondaryCheckbox:SetChecked(CompositePathValue(self._exCompositeDb, secondarySpec.key) == true)
        end
        -- 同一 CompositeHost 可被不同 key/来源集合的页面复用；先将每个已建立
        -- 控件的扁平字段映射重绑到本轮 key，再刷新显示，不能沿用上一页路径。
        for _, entry in ipairs(self._exCompositeControls or {}) do
            local fieldName = entry.control and entry.control._soundField
            if fieldName then
                entry.path = Field(fieldName)
                RefreshCompositeControl(entry, self._exCompositeDb)
            end
        end
        local packItems = ResolvePackItems()
        RebuildSourceState(state, packItems)
        local source = GetValue("source")
        if not state.allowed or not state.allowed[source] then
            source = state.defaultSource
            SetValue("source", source)
        end
        sourceDrop._items = state.dropdownSources or {}
        sourceDrop._currentValue = source
        SetDropdownDisplayText(sourceDrop, CompositeDropdownText(source, sourceDrop._items) or L["请选择..."])
        packDrop._items = packItems
        packDrop._currentValue = GetValue("label")
        SetDropdownDisplayText(packDrop, CompositeDropdownText(packDrop._currentValue, packItems) or L["请选择..."])
        if #packItems > 0 then
            if packDrop.Enable then packDrop:Enable() end
        elseif packDrop.Disable then
            packDrop:Disable()
        end
        if packDrop.EnableMouse then packDrop:EnableMouse(#packItems > 0) end
        packDrop:SetShown(source == "pack")
        lsmDrop:SetShown(source == "lsm")
        pathInput:SetShown(source == "file")
        ttsInput:SetShown(source == "tts")
    end
    group._exCompositeReflow = function(self, nextWidth, nextHeight)
        local layout = EXUI:BuildSoundGroupLayout(nextWidth, self._exCompositeOpts)
        if layout.isWide then
            -- 对应在线编辑器的标准比例：20 / 35 / 62 / 30 / 25。
            -- 当前音效位只会显示 LSM、路径或 TTS 三者之一。
            local padding = 15
            local scale = math.max(1, (nextWidth - padding * 2) / 193)
            local checkWidth = math.floor(20 * scale)
            local sourceWidth = math.floor(35 * scale)
            local soundWidth = math.floor(62 * scale)
            local channelWidth = math.floor(30 * scale)
            local testWidth = math.floor(25 * scale)
            local sourceX = padding + 24 * scale
            local soundX = padding + 62 * scale
            local channelX = padding + 128 * scale
            local testX = padding + 168 * scale
            header:SetSize(nextWidth, 40)
            content:SetSize(nextWidth, math.max(1, nextHeight - 40))
            settingsCard:ClearAllPoints(); settingsCard:SetPoint("TOPLEFT", content, "TOPLEFT")
            settingsCard:SetSize(nextWidth, math.max(1, nextHeight - 40))

            enabled:ClearAllPoints(); enabled:SetPoint("TOPLEFT", settingsCard, "TOPLEFT", padding, layout.enabledY); enabled:SetWidth(checkWidth)
            secondaryCheckbox:ClearAllPoints(); secondaryCheckbox:SetPoint("TOPLEFT", settingsCard, "TOPLEFT", padding, layout.secondaryY); secondaryCheckbox:SetWidth(checkWidth)
            sourceDrop:ClearAllPoints(); sourceDrop:SetPoint("TOPLEFT", settingsCard, "TOPLEFT", sourceX, layout.sourceY); sourceDrop:SetWidth(sourceWidth)
            for _, control in ipairs({ packDrop, lsmDrop, pathInput, ttsInput }) do
                control:ClearAllPoints(); control:SetPoint("TOPLEFT", settingsCard, "TOPLEFT", soundX, layout.sourceY); control:SetWidth(soundWidth)
            end
            channelDrop:ClearAllPoints(); channelDrop:SetPoint("TOPLEFT", settingsCard, "TOPLEFT", channelX, layout.channelY); channelDrop:SetWidth(channelWidth)
            testButton:ClearAllPoints(); testButton:SetPoint("TOPLEFT", settingsCard, "TOPLEFT", testX, layout.testY); testButton:SetWidth(testWidth)
            return
        end

        local padding, gap = 15, 18
        local itemWidth = math.max(140, math.floor((nextWidth - padding * 2 - gap) / 2))
        local col1, col2 = padding, padding + itemWidth + gap
        header:SetSize(nextWidth, 40)
        content:SetSize(nextWidth, math.max(1, nextHeight - 40))
        settingsCard:ClearAllPoints(); settingsCard:SetPoint("TOPLEFT", content, "TOPLEFT", padding, -8)
        settingsCard:SetSize(nextWidth - padding * 2, math.max(1, nextHeight - 56))
        enabled:ClearAllPoints(); enabled:SetPoint("TOPLEFT", settingsCard, "TOPLEFT", 10, layout.enabledY)
        secondaryCheckbox:ClearAllPoints(); secondaryCheckbox:SetPoint("TOPLEFT", settingsCard, "TOPLEFT", 10, layout.secondaryY)
        sourceDrop:ClearAllPoints(); sourceDrop:SetPoint("TOPLEFT", settingsCard, "TOPLEFT", col1, layout.sourceY); sourceDrop:SetWidth(itemWidth)
        for _, control in ipairs({ packDrop, lsmDrop, pathInput, ttsInput }) do
            control:ClearAllPoints(); control:SetPoint("TOPLEFT", settingsCard, "TOPLEFT", col2, layout.sourceY); control:SetWidth(itemWidth)
        end
        channelDrop:ClearAllPoints(); channelDrop:SetPoint("TOPLEFT", settingsCard, "TOPLEFT", col1, layout.channelY); channelDrop:SetWidth(itemWidth)
        testButton:ClearAllPoints(); testButton:SetPoint("TOPLEFT", settingsCard, "TOPLEFT", col2, layout.testY)
    end
    group:_exCompositeConfigure()
    group:_exCompositeReflow(groupWidth, groupHeight)
    AttachCompositeRelease(group)
    return group
end

-- =========================================================
-- [v4.4] Encounter Voice Group (池化版音效设置组)
-- =========================================================
if _G.ExwindFactory and not _G.ExwindFactory.Pools["GridVoiceGroup"] then
    _G.ExwindFactory:InitPool("GridVoiceGroup", "Frame", "BackdropTemplate", function(f)
        f:SetSize(750, 220)
        f._gridType = "GridVoiceGroup"
    end)
    if _G.ExwindFactory.GridTypeMap then
        _G.ExwindFactory.GridTypeMap["voicegroup"] = "GridVoiceGroup"
        _G.ExwindFactory.GridTypeMap["encounter_voice_group"] = "GridVoiceGroup"
    end
end

function EXUI:CreateVoiceGroup(parent, width, labelText, db, key, onUpdate)
    local w = width or 750
    local h = 170

    local EXFactory = _G.ExwindFactory
    local container

    if EXFactory then
        container = EXFactory:Acquire("GridVoiceGroup", parent)
        container:SetSize(w, h)
    else
        container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        container:SetSize(w, h)
    end

    container:SetBackdrop(nil)

    if not container._initialized then
        container.header = CreateFrame("Frame", nil, container)
        container.header:SetSize(w, 1)
        container.header:SetPoint("TOPLEFT")
        container.header:Hide()

        container.title = EXUI:CreateVisualFontString(container.header, EXFONTFRAME, "GameFontNormalHuge")
        container.title:SetPoint("LEFT", 15, 0)
        container.title:SetTextColor(0, 0.8, 1)

        local line = EXUI:CreateVisualTexture(container.header, EXBASEFRAME)
        line:SetPoint("BOTTOMLEFT", 10, 5)
        line:SetPoint("BOTTOMRIGHT", -10, 5)
        line:SetHeight(1)
        line:SetTexture("Interface\\Buttons\\WHITE8X8")
        line:SetGradient("HORIZONTAL", CreateColor(1, 1, 1, 0.5), CreateColor(1, 1, 1, 0.05))

        container.content = CreateFrame("Frame", nil, container)
        container.content:SetSize(w, h)
        container.content:SetPoint("TOPLEFT", 0, 0)

        container.rows = {}

        local triggerNames = {
            [0] = L["文本警报"],
            [1] = L["施法开始"],
            [2] = L["提前五秒"]
        }

        local channels = {
            { "Master",   "Master" },
            { "SFX",      "SFX" },
            { "Ambience", "Ambience" },
            { "Music",    "Music" },
            { "Dialog",   "Dialog" },
        }

        local sources = {
            { L["语音包"], "pack" },
            { L["LSM音效"], "lsm" },
            { L["自定义路径"], "file" }
        }

        local packOptions = {}
        if _G.EXBV_LABELS and type(_G.EXBV_LABELS) == "table" then
            for _, label in ipairs(_G.EXBV_LABELS) do
                if type(label) == "string" and label ~= "" then
                    table.insert(packOptions, { label, label })
                end
            end
        end
        if #packOptions == 0 then
            table.insert(packOptions, { L["注意"], L["注意"] })
        end

        local rowY = -15
        for i = 0, 2 do
            local row = CreateFrame("Frame", nil, container.content)
            row:SetSize(w, 45)
            row:SetPoint("TOPLEFT", 0, rowY)
            rowY = rowY - 50

            local w_chk = 110
            local w_src = 120
            local w_chan = 110
            local w_vol = 140
            local w_dyn = math.max(160, w - w_chk - w_src - w_chan - w_vol - 60)

            local off_chk = -2
            local off_src = off_chk + w_chk
            local off_dyn = off_src + w_src + 15
            local off_chan = off_dyn + w_dyn + 15
            local off_vol = off_chan + w_chan + 15

            local chk = EXUI:CreateCheckbox(row, triggerNames[i], false, function(checked)
                local rDb = container._currentDb and container._currentDb.triggers and container._currentDb.triggers[i]
                if rDb then rDb.enabled = checked end
                if container._currentOnUpdate then container._currentOnUpdate(container._currentDb) end
            end)
            chk:SetPoint("LEFT", off_chk, 0)

            local srcDrop = EXUI:CreateDropdown(row, w_src, L["来源"], sources, "pack", function(val)
                local rDb = container._currentDb and container._currentDb.triggers and container._currentDb.triggers[i]
                if rDb then rDb.sourceType = val end
                row.UpdateDynamicArea(rDb)
                if container._currentOnUpdate then container._currentOnUpdate(container._currentDb) end
            end)
            srcDrop:SetPoint("LEFT", off_src, 0)

            local dynArea = CreateFrame("Frame", nil, row)
            dynArea:SetSize(w_dyn, 30)
            dynArea:SetPoint("LEFT", off_dyn, 0)

            local packDrop = EXUI:CreateDropdown(dynArea, w_dyn, "", packOptions, L["注意"], function(val)
                local rDb = container._currentDb and container._currentDb.triggers and container._currentDb.triggers[i]
                if rDb then rDb.label = val end
                if container._currentOnUpdate then container._currentOnUpdate(container._currentDb) end
            end)
            packDrop:SetPoint("LEFT", 0, 0)

            local lsmDrop = EXUI:CreateLSMSoundDropdown(dynArea, w_dyn, "sound", "None", function(val)
                local rDb = container._currentDb and container._currentDb.triggers and container._currentDb.triggers[i]
                if rDb then rDb.customLSM = val end
                if container._currentOnUpdate then container._currentOnUpdate(container._currentDb) end
            end)
            lsmDrop:SetPoint("LEFT", 0, 0)

            local fileInput = EXUI:CreateEditBox(dynArea, "", w_dyn, 30, "", {})
            fileInput:SetPoint("LEFT", 0, 0)
            fileInput:SetScript("OnEditFocusLost", function(self)
                local rDb = container._currentDb and container._currentDb.triggers and container._currentDb.triggers[i]
                if rDb then rDb.customPath = self:GetText() end
                if self:GetText() == "" then self.placeholder:Show() end
                self:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.8)
                if container._currentOnUpdate then container._currentOnUpdate(container._currentDb) end
            end)
            fileInput:SetScript("OnEnterPressed", function(self)
                self:ClearFocus()
                local rDb = container._currentDb and container._currentDb.triggers and container._currentDb.triggers[i]
                if rDb then rDb.customPath = self:GetText() end
                if container._currentOnUpdate then container._currentOnUpdate(container._currentDb) end
            end)

            row.UpdateDynamicArea = function(t)
                local rDb = t or
                    (container._currentDb and container._currentDb.triggers and container._currentDb.triggers[i])
                if not rDb then return end
                packDrop:Hide()
                lsmDrop:Hide()
                fileInput:Hide()
                if rDb.sourceType == "pack" then
                    packDrop:Show()
                elseif rDb.sourceType == "lsm" then
                    lsmDrop:Show()
                else
                    fileInput:Show()
                end
            end

            local chanDrop = EXUI:CreateDropdown(row, w_chan, L["频道"], channels, "Master", function(val)
                local rDb = container._currentDb and container._currentDb.triggers and container._currentDb.triggers[i]
                if rDb then rDb.channel = val end
                if container._currentOnUpdate then container._currentOnUpdate(container._currentDb) end
            end)
            chanDrop:SetPoint("LEFT", off_chan, 0)

            local volSlider = EXUI:CreateSlider(row, w_vol, L["音量"], 0, 1, 1, 0.1, nil, function(v)
                local rDb = container._currentDb and container._currentDb.triggers and container._currentDb.triggers[i]
                if rDb then rDb.volume = v end
                if container._currentOnUpdate then container._currentOnUpdate(container._currentDb) end
            end)
            volSlider:SetPoint("LEFT", off_vol, 0)

            row.chk = chk
            row.srcDrop = srcDrop
            row.packDrop = packDrop
            row.lsmDrop = lsmDrop
            row.fileInput = fileInput
            row.chanDrop = chanDrop
            row.volSlider = volSlider

            container.rows[i] = row
        end

        container._initialized = true
    end

    container.title:SetText(labelText or L["语音设置组"])

    if type(db) ~= "table" then return container end
    db.triggers = type(db.triggers) == "table" and db.triggers or {}

    container._currentDb = db
    container._currentOnUpdate = onUpdate

    for i = 0, 2 do
        local r = container.rows[i]
        local t = db.triggers[i]
        if type(t) ~= "table" then
            t = {}
            db.triggers[i] = t
        end

        if not t.sourceType then t.sourceType = "pack" end
        if not t.channel then t.channel = "Master" end
        if not t.volume then t.volume = 1 end

        -- Apply values to Checkbox
        r.chk:SetChecked(t.enabled == true)

        -- Apply values to Source Dropdown
        r.srcDrop._currentValue = t.sourceType
        r.srcDrop:SetText(t.sourceType == "pack" and L["语音包"] or (t.sourceType == "lsm" and L["LSM音效"] or L["自定义路径"]))

        -- Apply values to Pack Dropdown
        r.packDrop._currentValue = t.label or L["注意"]
        r.packDrop:SetText(t.label or L["注意"])

        -- Apply values to LSM Dropdown
        r.lsmDrop._selectedValue = t.customLSM or "None"
        r.lsmDrop:SetText(t.customLSM or "None")

        -- Apply values to File Input
        r.fileInput:SetText(t.customPath or "")
        r.fileInput.placeholder:SetText(L["路径..."])
        if t.customPath and t.customPath ~= "" then
            r.fileInput.placeholder:Hide()
        else
            r.fileInput.placeholder:Show()
        end

        -- Apply values to Channel Dropdown
        r.chanDrop._currentValue = t.channel
        r.chanDrop:SetText(t.channel)

        -- Apply values to Volume Slider
        if r.volSlider.Init then r.volSlider:Init(t.volume, 0, 1, 10) end
        if r.volSlider.ValueText then r.volSlider.ValueText:SetText(string.format("%.1f", t.volume)) end

        -- Finally refresh Dynamic Area Visibility
        if r.UpdateDynamicArea then r.UpdateDynamicArea(t) end
    end

    container:Show()
    return container
end

-- =========================================================
-- 13. 输入框与多行文本框 (EditBox)
-- Options: .bgColor, .borderColor, .textColor
-- =========================================================
function EXUI:CreateEditBox(parent, text, w, h, labelText, options)
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

        -- 清理旧回调
        container:SetScript("OnTextChanged", nil)
        container:SetScript("OnEditFocusLost", nil)
        container:SetScript("OnEnterPressed", nil)

        -- 兼容旧接口
        container.editBox = container

        -- 基础配置
        SetPixelSize(container, w or 180, h or 28)
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

            -- 字体大小 (修正默认值)
            local font, _, flags = label:GetFont()
            local size = (options.labelSize and tonumber(options.labelSize)) or 14
            label:SetFont(font, size, flags)
        else
            container.label:Hide()
        end

        -- 占位符
        if not container.placeholder then
            container.placeholder = EXUI:CreateVisualFontString(container, EXFONTFRAME, "GameFontDisable")
            container.placeholder:SetPoint("LEFT", 3, 0)
        end
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

        container:SetScript("OnEditFocusGained", function(self)
            self:SetBackdropBorderColor(0.64, 0.19, 0.79, 1)
        end)

        container:SetScript("OnEditFocusLost", function(self)
            self:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
            UpdatePlaceholder()
            if options.onEditFocusLost then options.onEditFocusLost(self:GetText()) end
        end)

        container:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
            if options.onEnter then options.onEnter(self:GetText()) end
        end)

        container:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

        return container
    end

    -- =========================================================
    -- 多行模式或无工厂模式 (Legacy Path)
    -- =========================================================

    -- 1. 主容器 (Tooltip 风格)
    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    SetPixelSize(container, w, h)
    container:SetBackdrop(EXUI.TooltipBackdrop)
    container:SetBackdropColor(0, 0, 0, 0.6)
    container:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

    -- 简化的标签逻辑
    if labelText then
        local label = EXUI:CreateVisualFontString(container, EXFONTFRAME, "GameFontHighlightSmall")
        if options.labelPos == "left" then
            label:SetPoint("RIGHT", container, "LEFT", -5, 0)
            label:SetJustifyH("RIGHT")
        else
            label:SetPoint("BOTTOMLEFT", container, "TOPLEFT", 0, 3)
        end
        local font, _, flags = label:GetFont()
        local size = (options.labelSize and tonumber(options.labelSize)) or 14
        label:SetFont(font, size, flags)
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
        local parentScroll = EXUI.RightScrollFrame
        if parentScroll and parentScroll:IsShown() then
            local current = parentScroll:GetVerticalScroll()
            parentScroll:SetVerticalScroll(current - (delta * 25))
        end
    end
    sf:SetScript("OnMouseWheel", ForwardWheelToPage)
    eb:EnableMouseWheel(true)
    eb:HookScript("OnMouseWheel", ForwardWheelToPage)

    eb:SetAutoFocus(false)
    eb:SetText(text or "")
    eb:SetFontObject("GameFontHighlight")
    eb:SetTextInsets(8, 8, 8, 8) -- 增加边距，更有呼吸感

    -- [Fix] 更新高度以适应内容，确保滚动条逻辑生效
    eb:SetScript("OnTextChanged", function(self, userInput)
        -- 自动伸缩高度：取可视高度和内容高度的较大者
        local contentH = self:GetNumLetters() * 15 -- 粗略估算，或者直接保持固定大高度
        -- 更好的做法：不做自动伸缩，只依赖 ScrollFrame。但为了点击体验，保持 SetSize(..., h)
        if options.onChanged then options.onChanged(self:GetText(), userInput) end
    end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEditFocusGained", function() container:SetBackdropBorderColor(0.64, 0.19, 0.79, 1) end)
    eb:SetScript("OnEditFocusLost", function(self)
        container:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
        if options.onEditFocusLost then options.onEditFocusLost(self:GetText()) end
    end)

    container.editBox = eb
    function container:GetText() return self.editBox:GetText() end

    function container:SetText(t) self.editBox:SetText(t or "") end

    return container
end

-- =========================================================
-- 14. 交互式预览画板 (Interactive Preview Canvas)
-- =========================================================
function EXUI:CreatePreviewCanvas(parent, width, height, elementsData, callbacks)
    local canvas = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    canvas:SetSize(width, height)

    -- 画板背景 (网格或深色背景)
    canvas:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    canvas:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    canvas:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    -- 网格参考线 (辅助对齐)
    local gridLine = EXUI:CreateVisualTexture(canvas, EXBACKGROUNDFRAME)
    gridLine:SetAllPoints()
    gridLine:SetColorTexture(1, 1, 1, 0.05)

    local centerLineH = EXUI:CreateVisualTexture(canvas, EXBASEFRAME)
    centerLineH:SetHeight(1)
    centerLineH:SetPoint("LEFT"); centerLineH:SetPoint("RIGHT")
    centerLineH:SetPoint("CENTER")
    centerLineH:SetColorTexture(1, 1, 1, 0.2)

    local centerLineV = EXUI:CreateVisualTexture(canvas, EXBASEFRAME)
    centerLineV:SetWidth(1)
    centerLineV:SetPoint("TOP"); centerLineV:SetPoint("BOTTOM")
    centerLineV:SetPoint("CENTER")
    centerLineV:SetColorTexture(1, 1, 1, 0.2)

    canvas.elements = {}
    canvas.selectedKey = nil

    local onSelect = callbacks and callbacks.onSelect
    local onMove = callbacks and callbacks.onMove

    -- 内部方法：创建/更新子元素
    function canvas:UpdateElements(dataMap)
        -- 1. 隐藏所有旧元素
        for _, el in pairs(self.elements) do el:Hide() end

        -- 2. 遍历数据创建/显示元素
        for key, data in pairs(dataMap) do
            if data.enabled then
                local el = self.elements[key]
                if not el then
                    el = CreateFrame("Button", nil, self, "BackdropTemplate")
                    el:SetSize(100, 24) -- 默认基准大小
                    el:SetBackdrop({
                        bgFile = "Interface\\Buttons\\WHITE8X8",
                        edgeFile = "Interface\\Buttons\\WHITE8X8",
                        edgeSize = 1,
                    })

                    el.text = EXUI:CreateVisualFontString(el, EXFONTFRAME, "GameFontHighlightSmall")
                    el.text:SetPoint("CENTER")

                    -- 拖拽逻辑
                    el:SetMovable(true)
                    el:RegisterForDrag("LeftButton")
                    el:SetScript("OnDragStart", function(s)
                        if self.selectedKey ~= key then self:Select(key) end
                        s:StartMoving()
                    end)
                    el:SetScript("OnDragStop", function(s)
                        s:StopMovingOrSizing()
                        local cx, cy = self:GetCenter()
                        local ex, ey = s:GetCenter()

                        if not cx or not ex then return end

                        -- 计算相对坐标 (相对于 Canvas 中心)
                        local relX = ex - cx
                        local relY = ey - cy

                        -- 吸附逻辑 (简单取整)
                        relX = math.floor(relX + 0.5)
                        relY = math.floor(relY + 0.5)

                        s:ClearAllPoints()
                        s:SetPoint("CENTER", self, "CENTER", relX, relY)

                        if onMove then onMove(key, relX, relY) end
                    end)

                    -- 点击选择
                    el:SetScript("OnClick", function() self:Select(key) end)

                    self.elements[key] = el
                end

                -- 更新样式与位置
                el:Show()
                el.text:SetText(data.label or key)
                el:ClearAllPoints()
                el:SetPoint("CENTER", self, "CENTER", data.x or 0, data.y or 0)

                -- 根据是否选中设置外观
                if self.selectedKey == key then
                    el:SetBackdropColor(0, 0.5, 1, 0.6)
                    el:SetBackdropBorderColor(1, 1, 1, 1)
                else
                    el:SetBackdropColor(0.2, 0.2, 0.2, 0.6)
                    el:SetBackdropBorderColor(0, 0, 0, 0)
                end
            end
        end
    end

    function canvas:Select(key)
        self.selectedKey = key
        -- 刷新外观
        for k, el in pairs(self.elements) do
            if k == key then
                el:SetBackdropColor(0, 0.5, 1, 0.6)
                el:SetBackdropBorderColor(1, 1, 1, 1)
            else
                el:SetBackdropColor(0.2, 0.2, 0.2, 0.6)
                el:SetBackdropBorderColor(0, 0, 0, 0)
            end
        end
        if onSelect then onSelect(key) end
    end

    function canvas:ClearSelection()
        self:Select(nil)
    end

    if elementsData then
        canvas:UpdateElements(elementsData)
    end

    return canvas
end

-- =========================================================
-- 15. 分段控制器 (Segmented Control / Tabs)
-- items: { {label, value}, ... }
-- =========================================================
function EXUI:CreateSegmentedControl(parent, width, items, currentValue, onChange)
    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    local height = 32
    container:SetSize(width, height)

    -- 胶囊背景
    container:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    container:SetBackdropColor(0.1, 0.1, 0.1, 1)
    container:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    container.buttons = {}

    local numItems = #items
    local btnWidth = (width - 4) / numItems

    for i, item in ipairs(items) do
        local label, value = item[1], item[2]

        local btn = CreateFrame("Button", nil, container, "BackdropTemplate")
        btn:SetSize(btnWidth, height - 4)
        btn:SetPoint("LEFT", container, "LEFT", 2 + (i - 1) * btnWidth, 0)

        -- 选中态背景
        btn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
        btn:SetBackdropColor(0, 0, 0, 0) -- 默认透明

        local text = EXUI:CreateVisualFontString(btn, EXFONTFRAME, "GameFontHighlight")
        text:SetPoint("CENTER")
        text:SetText(label)
        btn.text = text

        btn:SetScript("OnClick", function()
            if currentValue == value then return end
            currentValue = value
            container:Refresh()
            if onChange then onChange(value) end
        end)

        btn.value = value
        container.buttons[i] = btn
    end

    -- 分割线
    for i = 1, numItems - 1 do
        local line = EXUI:CreateVisualTexture(container, EXBORDERFRAME)
        line:SetSize(1, height - 8)
        line:SetPoint("LEFT", container, "LEFT", 2 + i * btnWidth, 0)
        line:SetColorTexture(0.3, 0.3, 0.3, 1)
    end

    function container:Refresh()
        for _, btn in ipairs(self.buttons) do
            if btn.value == currentValue then
                -- 选中样式: 高亮背景 + 亮白文字
                btn:SetBackdropColor(0.2, 0.4, 0.8, 0.9)
                btn.text:SetTextColor(1, 1, 1)
            else
                -- 未选样式: 透明背景 + 灰色文字
                btn:SetBackdropColor(0, 0, 0, 0)
                btn.text:SetTextColor(0.6, 0.6, 0.6)
            end
        end
    end

    container:Refresh()

    return container
end

-- =========================================================
-- 16. 物品配置组件 (Item Config Widget)
-- 包含：Checkbox + Icon + ItemName + Input(Count) + DeleteBtn
-- 支持：物品拖拽（OnReceiveDrag）
-- =========================================================
function EXUI:CreateItemConfig(parent, width, height, itemID, db, onChange, onDelete)
    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    local w = width or 320
    local h = height or 40
    container:SetSize(w, h)

    -- 背景
    container:SetBackdrop(EXUI.TooltipBackdrop)
    container:SetBackdropColor(0, 0, 0, 0.4)
    container:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5)

    -- 1. 复选框 (启用/禁用)
    local cb = CreateFrame("CheckButton", nil, container, "MinimalCheckboxTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("LEFT", 5, 0)
    cb:SetChecked(db.enabled)
    cb:SetScript("OnClick", function(self)
        db.enabled = self:GetChecked()
        if onChange then onChange(db) end
    end)
    container.checkbox = cb

    -- 2. 物品图标
    local iconBtn = CreateFrame("Button", nil, container)
    iconBtn:SetSize(h - 10, h - 10)
    iconBtn:SetPoint("LEFT", cb, "RIGHT", 5, 0)
    local icon = EXUI:CreateVisualTexture(iconBtn, EXBASEFRAME)
    icon:SetAllPoints()
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    container.icon = icon

    -- 3. 物品名称
    local name = EXUI:CreateVisualFontString(container, EXFONTFRAME, "GameFontHighlightSmall")
    name:SetPoint("LEFT", iconBtn, "RIGHT", 8, 0)
    name:SetWidth(w - 140)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    container.nameText = name

    -- Tooltip 逻辑封装
    local function ShowTooltip(self)
        if itemID and itemID > 0 then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(itemID)
            GameTooltip:Show()
        end
    end
    local function HideTooltip() GameTooltip:Hide() end

    -- 物品加载逻辑
    local function UpdateItem(id)
        if not id or id == 0 then
            icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            name:SetText(L["可将消耗品拖进来添加"])
            name:SetTextColor(0.5, 0.5, 0.5)
            return
        end
        local itemName, _, quality, _, _, _, _, _, _, texture = C_Item.GetItemInfo(id)
        if itemName then
            icon:SetTexture(texture)
            name:SetText(itemName)
            local r, g, b = GetItemQualityColor(quality or 1)
            name:SetTextColor(r, g, b)
        else
            C_Item.RequestLoadItemDataByID(id)
            icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            name:SetText(L["数据加载中..."])
            C_Timer.After(0.5, function() UpdateItem(id) end)
        end
    end

    -- 事件上报逻辑
    local function HandleNewItemID(newID)
        local moduleKey = container.moduleKey
        local elementKey = container.elementKey
        if moduleKey and elementKey then
            ExwindTools:UpdateState(moduleKey .. ".ItemConfigUpdate", { key = elementKey, itemID = newID })
        end
        if onChange then onChange(db, newID) end
    end

    -- 绑定交互到容器：扩大 Tooltip 和拖放范围
    container:EnableMouse(true)
    container:SetScript("OnEnter", ShowTooltip)
    container:SetScript("OnLeave", HideTooltip)

    container:SetScript("OnReceiveDrag", function()
        local infoType, info1 = GetCursorInfo()
        local id
        if infoType == "item" then
            id = tonumber(info1)
        elseif infoType == "merchant" then
            id = GetMerchantItemID(info1)
        end

        if id then
            ClearCursor()
            UpdateItem(id)
            HandleNewItemID(id)
        end
    end)

    -- 同时也让图标按钮支持这些交互（因为层级在上）
    iconBtn:SetScript("OnEnter", ShowTooltip)
    iconBtn:SetScript("OnLeave", HideTooltip)
    iconBtn:RegisterForClicks("LeftButtonUp")
    iconBtn:SetScript("OnClick", function()
        local infoType, info1 = GetCursorInfo()
        local id
        if infoType == "item" then
            id = tonumber(info1)
        elseif infoType == "merchant" then
            id = GetMerchantItemID(info1)
        end

        if id then
            ClearCursor()
            UpdateItem(id)
            HandleNewItemID(id)
        end
    end)

    -- 4. 输入框
    local editBox = CreateFrame("EditBox", nil, container, "BackdropTemplate")
    editBox:SetSize(40, 24)
    editBox:SetPoint("RIGHT", -35, 0)
    editBox:SetBackdrop(EXUI.TooltipBackdrop)
    editBox:SetBackdropColor(0, 0, 0, 0.8)
    editBox:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    editBox:SetFontObject("GameFontHighlightSmall")
    editBox:SetJustifyH("CENTER")
    editBox:SetAutoFocus(false)
    editBox:SetNumeric(true)
    editBox:SetText(tostring(db.quantity or 1))
    editBox:SetScript("OnEnterPressed", function(self)
        db.quantity = tonumber(self:GetText()) or 1
        self:ClearFocus()
        if onChange then onChange(db) end
    end)
    editBox:SetScript("OnEditFocusLost", function(self)
        db.quantity = tonumber(self:GetText()) or 1
        if onChange then onChange(db) end
    end)
    container.editBox = editBox

    local qtyLabel = EXUI:CreateVisualFontString(container, EXFONTFRAME, "GameFontDisableSmall")
    qtyLabel:SetPoint("RIGHT", editBox, "LEFT", -5, 0)
    qtyLabel:SetText(L["数量"])

    -- 5. 修改后的删除按钮
    local delBtn = CreateFrame("Button", nil, container)
    delBtn:SetSize(20, 20)
    delBtn:SetPoint("RIGHT", -5, 0)
    delBtn:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    delBtn:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight")
    delBtn:SetScript("OnClick", function()
        local moduleKey = container.moduleKey
        local elementKey = container.elementKey
        if moduleKey and elementKey then
            ExwindTools:UpdateState(moduleKey .. ".ItemConfigDelete", { key = elementKey })
        end
        if onDelete and type(onDelete) == "function" then onDelete() end
    end)
    container.delBtn = delBtn
    -- 支持布尔值标记或函数回调
    if not onDelete then delBtn:Hide() end

    UpdateItem(itemID)
    return container
end

-- =========================================================
-- 12. Glow 设置复合组件 (Glow Settings Group)
-- =========================================================
function EXUI:CreateGlowSettings(parent, width, label, db, key, onUpdate)
    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    local groupWidth = width or 750
    local groupHeight = 280

    container:SetSize(groupWidth, groupHeight)

    -- 盒子外观
    container:SetBackdrop(EXUI.TooltipBackdrop)
    container:SetBackdropColor(0, 0, 0, 0.6)
    container:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.8)

    -- 标题区域
    local header = CreateFrame("Frame", nil, container)
    header:SetSize(groupWidth, 40)
    header:SetPoint("TOPLEFT")

    local title = EXUI:CreateVisualFontString(header, EXFONTFRAME, "GameFontNormalHuge")
    title:SetPoint("LEFT", 15, 0)
    title:SetText(label or L["发光样式"])
    title:SetTextColor(1, 0.82, 0)
    container.labelText = title

    local line = EXUI:CreateVisualTexture(header, EXBASEFRAME)
    line:SetPoint("BOTTOMLEFT", 10, 5)
    line:SetPoint("BOTTOMRIGHT", -10, 5)
    line:SetHeight(1)
    line:SetTexture("Interface\\Buttons\\WHITE8X8")
    line:SetGradient("HORIZONTAL", CreateColor(1, 1, 1, 0.5), CreateColor(1, 1, 1, 0.05))

    -- 内容容器
    local content = CreateFrame("Frame", nil, container)
    content:SetSize(groupWidth, groupHeight - 40)
    content:SetPoint("TOPLEFT", 0, -40)

    -- 布局坐标
    local col1, col2, col3 = 15, 275, 535
    local row1, row2, row3 = -25, -95, -165
    local itemW = 225

    local enableKey = key .. "Enabled"
    if db[enableKey] == nil then db[enableKey] = true end

    local cb = EXUI:CreateCheckbox(content, L["启用发光"], db[enableKey], function(checked)
        db[enableKey] = checked
        if onUpdate then onUpdate() end
    end)
    -- 注意：CreateCheckbox 返回一个容器，不是简单的 Button
    cb:SetPoint("TOPLEFT", col1, row1 - 5)


    -- 1. 样式选择 (Style Dropdown)
    local styleKey = key .. "Style"
    local styles = {
        { L["标准 (Classic)"], "Action Button Glow" },
        { L["像素 (Pixel)"], "Pixel Glow" },
        { L["自动施法 (AutoCast)"], "Autocast Shine" },
        { L["新版触发 (Proc)"], "Proc Glow" },
    }

    local styleDropdown = EXUI:CreateDropdown(content, itemW, L["样式类型"], styles, db[styleKey] or "Action Button Glow",
        function(val)
            db[styleKey] = val
            container:RefreshLayout()
            if onUpdate then onUpdate() end
        end)
    styleDropdown:SetPoint("TOPLEFT", col2, row1 - 10)

    -- 2. 颜色选择
    local colorBtn = EXUI:CreateColorButton(content, L["发光颜色"], db, key .. "Color", true, function()
        if onUpdate then onUpdate() end
    end)
    -- Color button matches generic button height
    colorBtn:SetPoint("TOPLEFT", col3, row1 - 10)

    -- 3. Sliders
    local sliders = {}
    local function CreateGlowSlider(sLabel, sKey, min, max, step, def)
        local itemKey = key .. sKey
        local s = EXUI:CreateSlider(content, itemW, sLabel, min, max, db[itemKey] or def, step, nil, function(v)
            db[itemKey] = v
            if onUpdate then onUpdate() end
        end)
        return s
    end

    sliders.Frequency = CreateGlowSlider(L["频率 (Frequency)"], "Frequency", 0.1, 5, 0.1, 0.25)
    sliders.Lines = CreateGlowSlider(L["线条 (Lines)"], "Lines", 1, 30, 1, 8)
    sliders.Scale = CreateGlowSlider(L["大小/粗细 (Scale)"], "Scale", 0.5, 3, 0.1, 1)
    sliders.Offset = CreateGlowSlider(L["边距 (Offset)"], "Offset", -50, 50, 1, 0)
    if db[key .. "Offset"] == nil then db[key .. "Offset"] = 0 end

    container.Sliders = sliders

    function container:RefreshLayout()
        local style = db[styleKey] or "Action Button Glow"

        if style == "Proc Glow" then colorBtn:Hide() else colorBtn:Show() end

        for _, s in pairs(sliders) do s:Hide() end

        -- Row 2 placement
        if style == "Action Button Glow" then
            sliders.Frequency:Show(); sliders.Frequency.Title:SetText(L["闪烁速度"]); sliders.Frequency:SetPoint("TOPLEFT", col1,
                row2)
        elseif style == "Pixel Glow" then
            sliders.Frequency:Show(); sliders.Frequency.Title:SetText(L["流动速度"]); sliders.Frequency:SetPoint("TOPLEFT", col1,
                row2)
            sliders.Lines:Show(); sliders.Lines.Title:SetText(L["线条数量"]); sliders.Lines:SetPoint("TOPLEFT", col2, row2)
            sliders.Scale:Show(); sliders.Scale.Title:SetText(L["线条粗细"]); sliders.Scale:SetPoint("TOPLEFT", col3, row2)
        elseif style == "Autocast Shine" then
            sliders.Frequency:Show(); sliders.Frequency.Title:SetText(L["闪烁速度"]); sliders.Frequency:SetPoint("TOPLEFT", col1,
                row2)
            sliders.Lines:Show(); sliders.Lines.Title:SetText(L["粒子数量"]); sliders.Lines:SetPoint("TOPLEFT", col2, row2)
            sliders.Scale:Show(); sliders.Scale.Title:SetText(L["粒子大小"]); sliders.Scale:SetPoint("TOPLEFT", col3, row2)
        end

        -- Row 3 placement (Offset)
        if style ~= "Proc Glow" then
            sliders.Offset:Show(); sliders.Offset:SetPoint("TOPLEFT", col1, row3)
        end
    end

    container:RefreshLayout()
    return container
end

-- =========================================================
-- 17. 图标设置组 (Icon Settings Group)
-- =========================================================
function EXUI:CreateIconGroup(parent, width, label, db, key, onUpdate, opts)
    opts = type(opts) == "table" and opts or {}
    local groupWidth = width or 750
    local groupHeight = 220

    -- [关键修复] 获取嵌套子表，如果不存在则初始化
    db = type(db) == "table" and db or {}
    if key and not db[key] then db[key] = {} end
    local iconDb = key and db[key] or db

    -- 图标四项开关的默认状态。nil 视为开启，既兼容旧配置，也让首次打开
    -- 设置页时与当前默认视觉保持一致。
    if iconDb.showIcon == nil then iconDb.showIcon = true end
    if iconDb.showBorder == nil then iconDb.showBorder = true end
    if iconDb.enableCrop == nil then iconDb.enableCrop = true end
    if iconDb.showCooldown == nil then iconDb.showCooldown = true end
    if iconDb.reverse == nil then iconDb.reverse = false end
    if type(iconDb.cooldown) ~= "table" then iconDb.cooldown = {} end
    local cooldownDb = iconDb.cooldown
    if cooldownDb.showSwipe == nil then cooldownDb.showSwipe = true end
    if cooldownDb.swipeAlpha == nil then cooldownDb.swipeAlpha = 0.65 end
    if cooldownDb.showEdge == nil then cooldownDb.showEdge = true end
    if cooldownDb.edgeAlpha == nil then cooldownDb.edgeAlpha = 1 end
    if cooldownDb.showBling == nil then cooldownDb.showBling = false end

    local container, isNew = AcquireCompositeGroup("CompositeIconGroup", parent)
    container._exCompositeLabel = label or L["图标设置"]
    BindCompositeGroup(container, iconDb, onUpdate, opts)
    if not isNew then
        AttachCompositeRelease(container)
        ReflowCompositeGroup(container, groupWidth, groupHeight)
        return container
    end
    iconDb = CreateCompositeProxy(container)
    cooldownDb = CreateCompositeProxy(container, "cooldown")
    opts = setmetatable({}, { __index = function(_, field)
        return (container._exCompositeOpts or {})[field]
    end })
    onUpdate = function() CompositeEmitUpdate(container) end

    local function GetIconInputMetadata()
        local activeOpts = container._exCompositeOpts or {}
        local metadata = activeOpts._exWriteContext
        if metadata == nil then return nil end
        if type(metadata) ~= "table" or type(metadata.moduleKey) ~= "string" or metadata.moduleKey == "" then
            error("CreateIconGroup requires Grid write context", 2)
        end
        local prefix = metadata.pathPrefix or metadata.path
        if type(prefix) ~= "string" or prefix == "" then
            error("CreateIconGroup Grid write context requires pathPrefix", 2)
        end
        local commitAPI = EXUI.CommitModuleValue
        if type(commitAPI) ~= "function" then
            error("CreateIconGroup requires its Core commit API", 2)
        end
        return metadata.moduleKey, prefix
    end

    -- IconGroup 的写入上下文只由 Grid 注入；每次值变化都经统一 ModuleDB
    -- 通知重套已存在表面。
    local function WriteIconSliderValue(field, value)
        local target, key = iconDb, field
        local parentPath, childKey = tostring(field):match("^(.*)%.([^%.]+)$")
        if parentPath == "cooldown" then
            target, key = cooldownDb, childKey
        end
        target[key] = value
    end

    local function ReadIconValue(field)
        local parentPath, childKey = tostring(field):match("^(.*)%.([^%.]+)$")
        if parentPath == "cooldown" then return cooldownDb[childKey] end
        return iconDb[field]
    end

    local function CommitIconValue(field, value)
        local moduleKey, prefix = GetIconInputMetadata()
        if moduleKey then
            local payload = {
                moduleKey = moduleKey, path = prefix .. "." .. field,
                readValue = function() return ReadIconValue(field) end,
                writeValue = function(nextValue) WriteIconSliderValue(field, nextValue) end,
            }
            return EXUI:CommitModuleValue(payload, value)
        end
        WriteIconSliderValue(field, value)
        if onUpdate then onUpdate() end
        return true
    end

    local function CreateIconColorTransaction(colorKey)
        local fields = colorKey == "borderColor"
            and { "borderColorR", "borderColorG", "borderColorB", "borderColorA" }
            or { "colorR", "colorG", "colorB", "colorA" }
        return function()
            -- 同 FontGroup：池化色盘必须在点击当下解析当前模块声明。
            local moduleKey, prefix = GetIconInputMetadata()
            if not moduleKey then return nil end
            local payload = {
                moduleKey = moduleKey, path = prefix .. "." .. colorKey,
                readValue = function()
                    return { r = iconDb[fields[1]], g = iconDb[fields[2]], b = iconDb[fields[3]], a = iconDb[fields[4]] }
                end,
                writeValue = function(value)
                    iconDb[fields[1]], iconDb[fields[2]], iconDb[fields[3]], iconDb[fields[4]] = value.r, value.g, value.b, value.a
                end,
            }
            return EXUI:CreateModuleNotifyFlow(payload)
        end
    end

    local function SetIconSliderValue(field, value, phase)
        WriteIconSliderValue(field, value)
        if phase ~= "live" and onUpdate then onUpdate() end
    end

    -- 旧 RegisterModuleLayout 的 IconGroup 可声明公开 registry 生命周期。每次
    -- 按下均从当前 pooled group 的 opts 解析，绝不复用上一模块的 moduleKey/path；
    local function CreateIconNotifyFlow(field)
        local activeOpts = container._exCompositeOpts or {}
        local transaction = activeOpts._exWriteContext
        if transaction ~= nil then
            if type(transaction) ~= "table" or type(transaction.moduleKey) ~= "string" or transaction.moduleKey == "" then
                error("CreateIconGroup requires Grid write context", 2)
            end
            local prefix = transaction.pathPrefix or transaction.path
            if type(prefix) ~= "string" or prefix == "" then
                error("CreateIconGroup Grid write context requires pathPrefix", 2)
            end
            local createAPI = EXUI.CreateModuleNotifyFlow
            if type(createAPI) ~= "function" then
                error("CreateIconGroup requires its Core transaction API", 2)
            end
            local payload = {
                moduleKey = transaction.moduleKey,
                path = prefix .. "." .. field,
                readValue = function()
                    local target, fieldKey = iconDb, field
                    local parentPath, childKey = tostring(field):match("^(.*)%.([^%.]+)$")
                    if parentPath == "cooldown" then target, fieldKey = cooldownDb, childKey end
                    return target[fieldKey]
                end,
                writeValue = function(value) WriteIconSliderValue(field, value) end,
            }
            return createAPI(EXUI, payload)
        end
        local metadata = activeOpts._exWriteContext
        if metadata == nil then return nil end
        if type(metadata) ~= "table" or type(metadata.moduleKey) ~= "string" or metadata.moduleKey == "" then
            error("CreateIconGroup requires Grid write context", 2)
        end
        local prefix = metadata.pathPrefix or metadata.path
        if type(prefix) ~= "string" or prefix == "" then
            error("CreateIconGroup Grid write context requires pathPrefix", 2)
        end
        if type(EXUI.CreateModuleNotifyFlow) ~= "function" then
            error("CreateIconGroup requires CreateModuleNotifyFlow", 2)
        end
        return EXUI:CreateModuleNotifyFlow({
            moduleKey = metadata.moduleKey,
            path = prefix .. "." .. field,
            readValue = function()
                local target, fieldKey = iconDb, field
                local parentPath, childKey = tostring(field):match("^(.*)%.([^%.]+)$")
                if parentPath == "cooldown" then target, fieldKey = cooldownDb, childKey end
                return target[fieldKey]
            end,
            writeValue = function(value)
                WriteIconSliderValue(field, value)
            end,
            commit = function(value)
                WriteIconSliderValue(field, value)
                if onUpdate then onUpdate() end
            end,
        })
    end

    local function CreateIconSlider(parentFrame, sliderWidth, titleText, field, minValue, maxValue, value, stepValue)
        local lifecycle
        return EXUI:CreateSlider(parentFrame, sliderWidth, titleText, minValue, maxValue, value, stepValue, nil, {
            onBegin = function()
                lifecycle = CreateIconNotifyFlow(field)
                if lifecycle and lifecycle.onBegin then lifecycle.onBegin() end
            end,
            onLive = function(v)
                if lifecycle and lifecycle.onLive then lifecycle.onLive(v) else SetIconSliderValue(field, v, "live") end
            end,
            onCommit = function(v)
                -- 同 FontGroup：数字输入是一次性提交，没有拖动期的 onBegin。
                local inputOpts = container._exCompositeOpts or {}
                if not lifecycle and inputOpts._exWriteContext ~= nil then
                    lifecycle = CreateIconNotifyFlow(field)
                end
                if lifecycle and lifecycle.onCommit then
                    lifecycle.onCommit(v)
                    lifecycle = nil
                else
                    SetIconSliderValue(field, v, "commit")
                end
            end,
        })
    end

    -- Protocol 风格：zinc-900 纯底色、低透明白线、少量 emerald 强调；不改全局皮肤。
    local palette = {
        panel = { 0.094, 0.094, 0.106, 1 }, -- zinc-900
        card = { 0.112, 0.112, 0.125, 1 },
        utility = { 0.106, 0.106, 0.118, 1 },
        border = { 1, 1, 1, 0.10 },
        borderSoft = { 1, 1, 1, 0.075 },
        text = { 0.96, 0.96, 0.97, 1 },
        value = { 0.204, 0.827, 0.599, 1 }, -- emerald-400
        accent = { 0.204, 0.827, 0.599, 1 },
    }
    local flatBackdrop = {
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    }

    -- Backdrop 的 1 UI 单位边缘在 ScrollFrame 中随滚动偏移时可能落在半个物理像素上，
    -- 低透明度下会像“消失”一样。外框改为四条绘制在框内的物理像素线，避免被裁切。
    local function AddCrispOutline(frame, color)
        local lines = {}
        for i = 1, 4 do
            local line = EXUI:CreateVisualTexture(frame, EXBORDERFRAME)
            line:SetTexture("Interface\\Buttons\\WHITE8X8")
            line:SetColorTexture(unpack(color))
            if line.SetSnapToPixelGrid then line:SetSnapToPixelGrid(true) end
            if line.SetTexelSnappingBias then line:SetTexelSnappingBias(0) end
            lines[i] = line
        end

        local function Update()
            local scale = frame:GetEffectiveScale()
            local pixel = 1 / ((scale and scale > 0) and scale or 1)

            lines[1]:ClearAllPoints()
            lines[1]:SetPoint("TOPLEFT", frame, "TOPLEFT")
            lines[1]:SetPoint("TOPRIGHT", frame, "TOPRIGHT")
            lines[1]:SetHeight(pixel)

            lines[2]:ClearAllPoints()
            lines[2]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT")
            lines[2]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT")
            lines[2]:SetHeight(pixel)

            lines[3]:ClearAllPoints()
            lines[3]:SetPoint("TOPLEFT", frame, "TOPLEFT")
            lines[3]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT")
            lines[3]:SetWidth(pixel)

            lines[4]:ClearAllPoints()
            lines[4]:SetPoint("TOPRIGHT", frame, "TOPRIGHT")
            lines[4]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT")
            lines[4]:SetWidth(pixel)
        end

        frame:HookScript("OnSizeChanged", Update)
        frame:HookScript("OnShow", Update)
        Update()
        return lines
    end

    container:SetSize(groupWidth, groupHeight)

    container:SetBackdrop(flatBackdrop)
    container:SetBackdropColor(unpack(palette.panel))
    container:SetBackdropBorderColor(unpack(palette.borderSoft))
    container.crispOutline = AddCrispOutline(container, palette.border)

    local header = CreateFrame("Frame", nil, container)
    header:SetSize(groupWidth, 40)
    header:SetPoint("TOPLEFT")

    local title = EXUI:CreateVisualFontString(header, EXFONTFRAME, "GameFontNormalHuge")
    title:SetPoint("LEFT", 15, 0)
    title:SetText(container._exCompositeLabel)
    title:SetTextColor(unpack(palette.text))
    container.labelText = title
    container._exCompositeTitle = title

    local titleAccent = EXUI:CreateVisualTexture(header, EXBASEFRAME)
    titleAccent:SetPoint("LEFT", 6, 0)
    titleAccent:SetSize(3, 21)
    titleAccent:SetColorTexture(unpack(palette.accent))

    local content = CreateFrame("Frame", nil, container)
    content:SetSize(groupWidth, groupHeight - 40)
    content:SetPoint("TOPLEFT", 0, -40)

    -- 左侧默认是 2x2 几何滑条；不需要模块局部图标偏移时可显式隐藏
    -- Position 控件，根锚点仍是该模块唯一的位置来源。
    local padding, gap = 15, 12
    local controlsGap = 18
    local controlWidth = math.min(416, math.max(364, math.floor(groupWidth * 0.40)))
    local metricsWidth = groupWidth - padding * 2 - controlsGap - controlWidth
    local itemWidth = math.floor((metricsWidth - gap) / 2)
    local col1 = padding
    local col2 = col1 + itemWidth + gap
    local row1, row2 = -8, -78
    local controlX = padding + metricsWidth + controlsGap

    -- 每个几何参数保留独立深色卡片，避免滑条直接裸排在内容区。
    local function CreateMetricCard(x, y)
        local card = CreateFrame("Frame", nil, content, "BackdropTemplate")
        card:SetPoint("TOPLEFT", x, y)
        card:SetSize(itemWidth, 64)
        card:SetBackdrop(flatBackdrop)
        card:SetBackdropColor(unpack(palette.card))
        card:SetBackdropBorderColor(unpack(palette.border))
        return card
    end

    local widthCard = CreateMetricCard(col1, row1)
    local heightCard = CreateMetricCard(col2, row1)
    local sliderWidth = itemWidth - 20

    local sWidth = CreateIconSlider(widthCard, sliderWidth, L["宽度 (Width)"], "width", 10, 300, iconDb.width or 64, 1)
    sWidth:SetPoint("TOPLEFT", 10, -31)

    local sHeight = CreateIconSlider(heightCard, sliderWidth, L["高度 (Height)"], "height", 10, 300, iconDb.height or 64, 1)
    sHeight:SetPoint("TOPLEFT", 10, -31)

    local sPosX, sPosY, xCard, yCard
    if opts.hidePositionControls ~= true then
        xCard = CreateMetricCard(col1, row2)
        yCard = CreateMetricCard(col2, row2)
        -- Aura 图标可用较细的偏移范围；排序和间距属于另一张“排序”卡片，绝不由这里重算。
        local offsetMin = tonumber(opts.offsetMin) or -1000
        local offsetMax = tonumber(opts.offsetMax) or 1000
        local offsetStep = tonumber(opts.offsetStep) or 1
        sPosX = CreateIconSlider(xCard, sliderWidth, L["水平偏移 (X)"], "x", offsetMin, offsetMax, iconDb.x or 0, offsetStep)
        sPosX:SetPoint("TOPLEFT", 10, -31)

        sPosY = CreateIconSlider(yCard, sliderWidth, L["垂直偏移 (Y)"], "y", offsetMin, offsetMax, iconDb.y or 0, offsetStep)
        sPosY:SetPoint("TOPLEFT", 10, -31)
    end

    local function StyleMetricSlider(slider)
        if slider.labelText then slider.labelText:SetTextColor(unpack(palette.text)) end
        if slider.ValueText then slider.ValueText:SetTextColor(unpack(palette.value)) end
    end
    StyleMetricSlider(sWidth)
    StyleMetricSlider(sHeight)
    if sPosX then StyleMetricSlider(sPosX) end
    if sPosY then StyleMetricSlider(sPosY) end

    -- 四项功能控制区：每一行左侧开关、右侧对应设置按钮。
    local actionCard = CreateFrame("Frame", nil, content, "BackdropTemplate")
    actionCard:SetPoint("TOPLEFT", controlX, row1)
    actionCard:SetSize(controlWidth, math.abs(row2 - row1) + 64)
    actionCard:SetBackdrop(flatBackdrop)
    actionCard:SetBackdropColor(unpack(palette.utility))
    actionCard:SetBackdropBorderColor(1, 1, 1, 0.16)

    local cbShow = EXUI:CreateCheckbox(actionCard, L["显示图标"], iconDb.showIcon, function(v)
        CommitIconValue("showIcon", v)
    end)
    cbShow:SetPoint("TOPLEFT", 12, -4)
    cbShow:SetSize(132, 28)
    cbShow.label:SetTextColor(unpack(palette.text))
    if cbShow.checkbox:GetCheckedTexture() then
        cbShow.checkbox:GetCheckedTexture():SetVertexColor(unpack(palette.accent))
    end

    local cbShowBorder = EXUI:CreateCheckbox(actionCard, L["显示边框"], iconDb.showBorder, function(v)
        CommitIconValue("showBorder", v)
    end)
    cbShowBorder:SetPoint("TOPLEFT", 12, -38)
    cbShowBorder:SetSize(132, 28)
    cbShowBorder.label:SetTextColor(unpack(palette.text))
    if cbShowBorder.checkbox:GetCheckedTexture() then
        cbShowBorder.checkbox:GetCheckedTexture():SetVertexColor(unpack(palette.accent))
    end

    local cbCrop = EXUI:CreateCheckbox(actionCard, L["裁切图标"], iconDb.enableCrop, function(v)
        CommitIconValue("enableCrop", v)
    end)
    cbCrop:SetPoint("TOPLEFT", 12, -72)
    cbCrop:SetSize(132, 28)
    cbCrop.label:SetTextColor(unpack(palette.text))
    if cbCrop.checkbox:GetCheckedTexture() then
        cbCrop.checkbox:GetCheckedTexture():SetVertexColor(unpack(palette.accent))
    end

    local cbCooldown = EXUI:CreateCheckbox(actionCard, L["图标倒数"], iconDb.showCooldown, function(v)
        CommitIconValue("showCooldown", v)
    end)
    cbCooldown:SetPoint("TOPLEFT", 12, -106)
    cbCooldown:SetSize(132, 28)
    cbCooldown.label:SetTextColor(unpack(palette.text))
    if cbCooldown.checkbox:GetCheckedTexture() then
        cbCooldown.checkbox:GetCheckedTexture():SetVertexColor(unpack(palette.accent))
    end

    local function CreatePopup(titleText, width, height)
        local popup = CreateCompositePopupHost(container, width, height)
        popup:SetBackdrop(flatBackdrop)
        popup:SetBackdropColor(unpack(palette.panel))
        popup:SetBackdropBorderColor(unpack(palette.border))
        popup:Hide()

        local popupTitle = EXUI:CreateVisualFontString(popup, EXFONTFRAME, "GameFontHighlight")
        popupTitle:SetPoint("TOPLEFT", 13, -9)
        popupTitle:SetText(titleText)
        popupTitle:SetTextColor(unpack(palette.text))

        local close = EXUI:CreateButton(popup, 28, 24, "×", function()
            popup:Hide()
        end)
        close:SetPoint("TOPRIGHT", -7, -4)
        return popup
    end

    local popupScale = 1.3
    local appearancePopupW = math.floor(400 * popupScale)
    local appearancePopup = CreatePopup(L["外观设置"], appearancePopupW, 254)
    local countdownPopupW, countdownPopupH = math.floor(400 * popupScale), 212
    local countdownPopup = CreatePopup(L["倒数设置"], countdownPopupW, countdownPopupH)
    local appearancePad, appearanceGap = 14, 18
    local appearanceItemW = math.floor((appearancePopupW - appearancePad * 2 - appearanceGap) / 2)

    -- central basicIcon 的图标来源属于业务 item，不是外观 DB；该中央分支不许
    -- CreateIconGroup 偷建/编辑 legacy iconID。旧页面保持原来的可选输入框。
    if opts.hideIconID ~= true then
        local inputIcon = EXUI:CreateEditBox(
            appearancePopup,
            tostring(iconDb.iconID or ""),
            appearanceItemW,
            32,
            L["图标ID (可选)"],
            {
                onEnter = function(v)
                    CommitIconValue("iconID", tonumber(v) or nil)
                end,
                onEditFocusLost = function(v)
                    CommitIconValue("iconID", tonumber(v) or nil)
                end,
                labelPos = "top"
            }
        )
        inputIcon:SetPoint("TOPLEFT", appearancePad, -44)
    end

    local alpha = CreateIconSlider(appearancePopup, appearanceItemW, L["图标透明度"], "alpha", 0, 1,
        tonumber(iconDb.alpha) or 1, 0.05)
    alpha:SetPoint("TOPLEFT", appearancePad + appearanceItemW + appearanceGap, -40)
    StyleMetricSlider(alpha)

    local cbDesaturated = EXUI:CreateCheckbox(appearancePopup, L["图标变灰"], iconDb.desaturated, function(v)
        CommitIconValue("desaturated", v)
    end)
    cbDesaturated:SetPoint("TOPLEFT", appearancePad, -92)
    cbDesaturated.label:SetTextColor(unpack(palette.text))
    if cbDesaturated.checkbox:GetCheckedTexture() then
        cbDesaturated.checkbox:GetCheckedTexture():SetVertexColor(unpack(palette.accent))
    end

    local iconColor = EXUI:CreateColorButton(appearancePopup, L["图标染色"], iconDb, "color", true, onUpdate,
        { _changeFlow = CreateIconColorTransaction("color") })
    iconColor:SetPoint("TOPLEFT", appearancePad, -128)

    local blendDrop = EXUI:CreateDropdown(appearancePopup, appearanceItemW, L["混合模式"], {
        { "BLEND", "BLEND" },
        { "ADD", "ADD" },
        { "MOD", "MOD" },
        { "ALPHAKEY", "ALPHAKEY" },
        { "DISABLE", "DISABLE" },
    }, iconDb.blendMode or "BLEND", function(v)
        CommitIconValue("blendMode", v)
    end)
    blendDrop:SetPoint("TOPLEFT", appearancePad + appearanceItemW + appearanceGap, -132)

    local rotation = CreateIconSlider(appearancePopup, appearanceItemW, L["旋转角度"], "rotation", -180, 180,
        tonumber(iconDb.rotation) or 0, 1)
    rotation:SetPoint("TOPLEFT", appearancePad, -202)
    StyleMetricSlider(rotation)

    local popupW, popupH = math.floor(580 * popupScale), 154
    local cropPopup = CreatePopup(L["裁切设置"], popupW, popupH)
    local borderPopup = CreatePopup(L["边框设置"], popupW, popupH)
    local popupPad, popupGap = 14, 18
    local popupItemW = math.floor((popupW - popupPad * 2 - popupGap) / 2)
    local popupCol1 = popupPad
    local popupCol2 = popupCol1 + popupItemW + popupGap

    local cropLeft = CreateIconSlider(cropPopup, popupItemW, L["裁切左 (Crop Left)"], "cropLeft", 0, 1,
        tonumber(iconDb.cropLeft) or 0.08, 0.01)
    cropLeft:SetPoint("TOPLEFT", popupCol1, -48)

    local cropRight = CreateIconSlider(cropPopup, popupItemW, L["裁切右 (Crop Right)"], "cropRight", 0, 1,
        tonumber(iconDb.cropRight) or 0.92, 0.01)
    cropRight:SetPoint("TOPLEFT", popupCol2, -48)

    local cropTop = CreateIconSlider(cropPopup, popupItemW, L["裁切上 (Crop Top)"], "cropTop", 0, 1,
        tonumber(iconDb.cropTop) or 0.08, 0.01)
    cropTop:SetPoint("TOPLEFT", popupCol1, -101)

    local cropBottom = CreateIconSlider(cropPopup, popupItemW, L["裁切下 (Crop Bottom)"], "cropBottom", 0, 1,
        tonumber(iconDb.cropBottom) or 0.92, 0.01)
    cropBottom:SetPoint("TOPLEFT", popupCol2, -101)
    StyleMetricSlider(cropLeft)
    StyleMetricSlider(cropRight)
    StyleMetricSlider(cropTop)
    StyleMetricSlider(cropBottom)

    local borderBtn = EXUI:CreateColorButton(borderPopup, L["边框颜色"], iconDb, "borderColor", true, onUpdate,
        { _changeFlow = CreateIconColorTransaction("borderColor") })
    borderBtn:SetPoint("TOPLEFT", popupCol1, -48)

    local borderDrop = EXUI:CreateLSMTextureDropdown(borderPopup, "border", popupItemW, L["边框材质"],
        iconDb.borderTexture or "None",
        function(k)
            CommitIconValue("borderTexture", k)
        end)
    borderDrop:SetPoint("TOPLEFT", popupCol2, -48)

    local sBorderSize = CreateIconSlider(borderPopup, popupItemW, L["边框粗细"], "borderSize", -10, 10,
        iconDb.borderSize or 1, 0.1)
    sBorderSize:SetPoint("TOPLEFT", popupCol1, -101)

    local sBorderPad = CreateIconSlider(borderPopup, popupItemW, L["边框间距 (Padding)"], "borderPadding", -10, 10,
        iconDb.borderPadding or 0, 0.1)
    sBorderPad:SetPoint("TOPLEFT", popupCol2, -101)
    StyleMetricSlider(sBorderSize)
    StyleMetricSlider(sBorderPad)

    -- 图标倒数的原生扇形视觉全部收口于此；数字文本由统一文本控件接管。
    local cbReverse = EXUI:CreateCheckbox(countdownPopup, L["倒数反转"], iconDb.reverse, function(v)
        CommitIconValue("reverse", v)
    end)
    cbReverse:SetPoint("TOPLEFT", 14, -42)
    cbReverse:SetSize(156, 28)
    cbReverse.label:SetTextColor(unpack(palette.text))
    if cbReverse.checkbox:GetCheckedTexture() then
        cbReverse.checkbox:GetCheckedTexture():SetVertexColor(unpack(palette.accent))
    end

    local countdownPad, countdownGap = 14, 18
    local countdownItemW = math.floor((countdownPopupW - countdownPad * 2 - countdownGap) / 2)
    local countdownCol2 = countdownPad + countdownItemW + countdownGap

    local cbSwipe = EXUI:CreateCheckbox(countdownPopup, L["启用扇形倒数"], cooldownDb.showSwipe, function(v)
        CommitIconValue("cooldown.showSwipe", v)
    end)
    cbSwipe:SetPoint("TOPLEFT", countdownCol2, -42)
    cbSwipe:SetSize(156, 28)
    cbSwipe.label:SetTextColor(unpack(palette.text))
    if cbSwipe.checkbox:GetCheckedTexture() then
        cbSwipe.checkbox:GetCheckedTexture():SetVertexColor(unpack(palette.accent))
    end

    local cbEdge = EXUI:CreateCheckbox(countdownPopup, L["显示边缘光"], cooldownDb.showEdge, function(v)
        CommitIconValue("cooldown.showEdge", v)
    end)
    cbEdge:SetPoint("TOPLEFT", countdownPad, -76)
    cbEdge:SetSize(156, 28)
    cbEdge.label:SetTextColor(unpack(palette.text))
    if cbEdge.checkbox:GetCheckedTexture() then
        cbEdge.checkbox:GetCheckedTexture():SetVertexColor(unpack(palette.accent))
    end

    local cbBling = EXUI:CreateCheckbox(countdownPopup, L["倒数结束闪光"], cooldownDb.showBling, function(v)
        CommitIconValue("cooldown.showBling", v)
    end)
    cbBling:SetPoint("TOPLEFT", countdownCol2, -76)
    cbBling:SetSize(176, 28)
    cbBling.label:SetTextColor(unpack(palette.text))
    if cbBling.checkbox:GetCheckedTexture() then
        cbBling.checkbox:GetCheckedTexture():SetVertexColor(unpack(palette.accent))
    end

    local swipeAlpha = CreateIconSlider(countdownPopup, countdownItemW, L["扇形透明度"], "cooldown.swipeAlpha", 0, 1,
        cooldownDb.swipeAlpha, 0.05)
    swipeAlpha:SetPoint("TOPLEFT", countdownPad, -128)

    local edgeAlpha = CreateIconSlider(countdownPopup, countdownItemW, L["边缘光透明度"], "cooldown.edgeAlpha", 0, 1,
        cooldownDb.edgeAlpha, 0.05)
    edgeAlpha:SetPoint("TOPLEFT", countdownCol2, -128)
    StyleMetricSlider(swipeAlpha)
    StyleMetricSlider(edgeAlpha)

    local function TogglePopup(popup, anchor, point, relativePoint)
        local shouldShow = not popup:IsShown()
        appearancePopup:Hide()
        cropPopup:Hide()
        borderPopup:Hide()
        countdownPopup:Hide()
        if shouldShow then
            popup:ClearAllPoints()
            popup:SetPoint(point, anchor, relativePoint, 0, -6)
            popup:Show()
        end
    end

    -- 本组专用平面按钮：不使用全局按钮的金属黑框，也不影响其他 GUI。
    local function CreateUtilityButton(text, width, onClick)
        local button = CreateFrame("Button", nil, actionCard, "BackdropTemplate")
        button:SetSize(width, 28)
        button:RegisterForClicks("LeftButtonUp")
        button:SetBackdrop(flatBackdrop)
        button:SetBackdropColor(0.06, 0.15, 0.12, 0.72)
        button:SetBackdropBorderColor(0.204, 0.827, 0.599, 0.22)

        local textLabel = EXUI:CreateVisualFontString(button, EXFONTFRAME, "GameFontHighlightSmall")
        textLabel:SetPoint("CENTER", 0, -1)
        textLabel:SetText(text)
        textLabel:SetTextColor(unpack(palette.accent))

        button:SetScript("OnEnter", function()
            button:SetBackdropColor(0.07, 0.20, 0.15, 0.86)
            button:SetBackdropBorderColor(0.204, 0.827, 0.599, 0.58)
            textLabel:SetTextColor(0.75, 0.96, 0.86, 1)
        end)
        button:SetScript("OnLeave", function()
            button:SetBackdropColor(0.06, 0.15, 0.12, 0.72)
            button:SetBackdropBorderColor(0.204, 0.827, 0.599, 0.22)
            textLabel:SetTextColor(unpack(palette.accent))
        end)
        button:SetScript("OnClick", onClick)
        return button
    end

    local buttonWidth = math.min(187, math.floor(controlWidth * 0.45))
    local appearanceButton = CreateUtilityButton(L["外观设置"], buttonWidth, function(self)
        TogglePopup(appearancePopup, self, "TOPRIGHT", "BOTTOMRIGHT")
    end)
    appearanceButton:SetPoint("TOPRIGHT", actionCard, "TOPRIGHT", -10, -4)

    local borderButton = CreateUtilityButton(L["边框设置"], buttonWidth, function(self)
        TogglePopup(borderPopup, self, "TOPRIGHT", "BOTTOMRIGHT")
    end)
    borderButton:SetPoint("TOPRIGHT", actionCard, "TOPRIGHT", -10, -38)

    local cropButton = CreateUtilityButton(L["裁切设置"], buttonWidth, function(self)
        TogglePopup(cropPopup, self, "TOPRIGHT", "BOTTOMRIGHT")
    end)
    cropButton:SetPoint("TOPRIGHT", actionCard, "TOPRIGHT", -10, -72)

    local countdownButton = CreateUtilityButton(L["倒数设置"], buttonWidth, function(self)
        TogglePopup(countdownPopup, self, "TOPRIGHT", "BOTTOMRIGHT")
    end)
    countdownButton:SetPoint("TOPRIGHT", actionCard, "TOPRIGHT", -10, -106)

    container:HookScript("OnHide", function()
        appearancePopup:Hide()
        cropPopup:Hide()
        borderPopup:Hide()
        countdownPopup:Hide()
    end)

    RegisterCompositeControl(container, sWidth, "width", "slider")
    RegisterCompositeControl(container, sHeight, "height", "slider")
    if sPosX then RegisterCompositeControl(container, sPosX, "x", "slider") end
    if sPosY then RegisterCompositeControl(container, sPosY, "y", "slider") end
    RegisterCompositeControl(container, cbShow, "showIcon", "check")
    RegisterCompositeControl(container, cbShowBorder, "showBorder", "check")
    RegisterCompositeControl(container, cbCrop, "enableCrop", "check")
    RegisterCompositeControl(container, cbCooldown, "showCooldown", "check")
    RegisterCompositeControl(container, inputIcon, "iconID", "edit")
    RegisterCompositeControl(container, alpha, "alpha", "slider")
    RegisterCompositeControl(container, cbDesaturated, "desaturated", "check")
    RegisterCompositeControl(container, iconColor, "color", "color")
    RegisterCompositeControl(container, blendDrop, "blendMode", "dropdown")
    RegisterCompositeControl(container, rotation, "rotation", "slider")
    RegisterCompositeControl(container, cropLeft, "cropLeft", "slider")
    RegisterCompositeControl(container, cropRight, "cropRight", "slider")
    RegisterCompositeControl(container, cropTop, "cropTop", "slider")
    RegisterCompositeControl(container, cropBottom, "cropBottom", "slider")
    RegisterCompositeControl(container, borderBtn, "borderColor", "color")
    RegisterCompositeControl(container, borderDrop, "borderTexture", "dropdown")
    RegisterCompositeControl(container, sBorderSize, "borderSize", "slider")
    RegisterCompositeControl(container, sBorderPad, "borderPadding", "slider")
    RegisterCompositeControl(container, cbReverse, "reverse", "check")
    RegisterCompositeControl(container, cbSwipe, "cooldown.showSwipe", "check")
    RegisterCompositeControl(container, cbEdge, "cooldown.showEdge", "check")
    RegisterCompositeControl(container, cbBling, "cooldown.showBling", "check")
    RegisterCompositeControl(container, swipeAlpha, "cooldown.swipeAlpha", "slider")
    RegisterCompositeControl(container, edgeAlpha, "cooldown.edgeAlpha", "slider")
    container._exCompositePopups = { appearancePopup, cropPopup, borderPopup, countdownPopup }
    container._iconGroupDb = iconDb
    container._exCompositeReflow = function(self, nextWidth, nextHeight)
        local nextControlWidth = math.min(416, math.max(364, math.floor(nextWidth * 0.40)))
        local nextMetricsWidth = nextWidth - padding * 2 - controlsGap - nextControlWidth
        local nextItemWidth = math.floor((nextMetricsWidth - gap) / 2)
        local nextCol2 = padding + nextItemWidth + gap
        local nextControlX = padding + nextMetricsWidth + controlsGap
        local nextSliderWidth = nextItemWidth - 20

        header:SetSize(nextWidth, 40)
        content:SetSize(nextWidth, nextHeight - 40)
        local metricCards = { widthCard, heightCard }
        if xCard then metricCards[#metricCards + 1] = xCard end
        if yCard then metricCards[#metricCards + 1] = yCard end
        for _, card in ipairs(metricCards) do card:SetSize(nextItemWidth, 64) end
        widthCard:ClearAllPoints(); widthCard:SetPoint("TOPLEFT", content, "TOPLEFT", col1, row1)
        heightCard:ClearAllPoints(); heightCard:SetPoint("TOPLEFT", content, "TOPLEFT", nextCol2, row1)
        if xCard then xCard:ClearAllPoints(); xCard:SetPoint("TOPLEFT", content, "TOPLEFT", col1, row2) end
        if yCard then yCard:ClearAllPoints(); yCard:SetPoint("TOPLEFT", content, "TOPLEFT", nextCol2, row2) end
        local metricSliders = { sWidth, sHeight }
        if sPosX then metricSliders[#metricSliders + 1] = sPosX end
        if sPosY then metricSliders[#metricSliders + 1] = sPosY end
        for _, slider in ipairs(metricSliders) do slider:SetWidth(nextSliderWidth) end
        actionCard:ClearAllPoints(); actionCard:SetPoint("TOPLEFT", content, "TOPLEFT", nextControlX, row1)
        actionCard:SetSize(nextControlWidth, math.abs(row2 - row1) + 64)
        local nextButtonWidth = math.min(187, math.floor(nextControlWidth * 0.45))
        appearanceButton:SetWidth(nextButtonWidth); borderButton:SetWidth(nextButtonWidth)
        cropButton:SetWidth(nextButtonWidth); countdownButton:SetWidth(nextButtonWidth)
    end
    container:_exCompositeReflow(groupWidth, groupHeight)
    AttachCompositeRelease(container)

    return container
end

-- =========================================================
-- 18. 计时条设置组（TimerBarWidget 对应的配置 GUI）
-- =========================================================
function EXUI:CreateTimerBarGroup(parent, width, label, db, key, onUpdate, opts)
    if key and type(db) == "table" then
        db[key] = type(db[key]) == "table" and db[key] or {}
        db = db[key]
    end
    db = type(db) == "table" and db or {}
    opts = type(opts) == "table" and opts or {}
    local iconOffsetMin = tonumber(opts.iconOffsetMin) or -200
    local iconOffsetMax = tonumber(opts.iconOffsetMax) or 200
    local defaults = {
        width = 240, height = 24, x = 0, y = 0,
        texture = "Clean",
        barColorR = 1, barColorG = 0.7, barColorB = 0, barColorA = 1,
        barBgColorR = 0, barBgColorG = 0, barBgColorB = 0, barBgColorA = 0.5,
        showBorder = true, borderTexture = "None", borderSize = 1, borderPadding = 0,
        borderColorR = 1, borderColorG = 1, borderColorB = 1, borderColorA = 1,
        showIcon = true, iconWidth = 24, iconHeight = 24, iconSide = "LEFT",
        iconOffsetX = -5, iconOffsetY = 0,
        showIconBorder = true, iconBorderTexture = "None", iconBorderSize = 1, iconBorderPadding = 0,
        iconBorderColorR = 1, iconBorderColorG = 1, iconBorderColorB = 1, iconBorderColorA = 1,
        fillMode = opts.fillModeOnly == true and "LTR_FILL" or "RTL_DRAIN", fillDirection = "LEFT_TO_RIGHT", progressMode = "REMAINING",
    }
    if opts.fillModeOnly == true then
        defaults.fillDirection, defaults.progressMode = nil, nil
    end
    for field, value in pairs(defaults) do
        if db[field] == nil then db[field] = value end
    end
    local groupWidth, groupHeight = width or 975, 282
    -- 层数条复用计时条的尺寸／材质／颜色／边框控件，但没有 duration、图标或填充模式语义。
    -- 使用独立对象池，避免普通计时条和层数条之间残留可见控件。
    local poolType = opts.applicationBar == true and "CompositeTimerBarApplicationGroup" or "CompositeTimerBarGroup"
    local group, isNew = AcquireCompositeGroup(poolType, parent)
    group._exCompositeLabel = label or L["计时条设置"]
    BindCompositeGroup(group, db, onUpdate, opts)
    -- TimerBar 的真实 DB 路径只由 Grid 的私有写入上下文提供。
    local function CreateTimerBarNotifyFlow(field)
        local metadata = group._exCompositeOpts and group._exCompositeOpts._exWriteContext
        if metadata == nil then return nil end
        if type(metadata) ~= "table" or type(metadata.moduleKey) ~= "string" or metadata.moduleKey == ""
            or type(metadata.pathPrefix) ~= "string" then
            error("CreateTimerBarGroup requires Grid write context", 2)
        end
        if type(EXUI.CreateModuleNotifyFlow) ~= "function" then
            error("CreateTimerBarGroup requires CreateModuleNotifyFlow", 2)
        end
        return EXUI:CreateModuleNotifyFlow({
            moduleKey = metadata.moduleKey,
            path = metadata.pathPrefix .. "." .. field,
            readValue = function() return db[field] end,
            writeValue = function(value) db[field] = value end,
            commit = function(value)
                db[field] = value
                CompositeEmitUpdate(group)
            end,
        })
    end
    -- 已声明的 TimerBarGroup 全部控件均走统一通知流。
    local function CreateTimerBarNotifyFlowForValue(field, readValue, writeValue)
        local activeOpts = group._exCompositeOpts or {}
        local metadata = activeOpts._exWriteContext
        if metadata == nil then return nil end
        if type(metadata) ~= "table" or type(metadata.moduleKey) ~= "string" or metadata.moduleKey == ""
            or type(metadata.pathPrefix) ~= "string" or metadata.pathPrefix == "" then
            error("CreateTimerBarGroup requires Grid write context", 2)
        end
        local createAPI = EXUI.CreateModuleNotifyFlow
        if type(createAPI) ~= "function" then
            error("CreateTimerBarGroup requires CreateModuleNotifyFlow", 2)
        end
        return createAPI(EXUI, {
            moduleKey = metadata.moduleKey,
            path = metadata.pathPrefix .. "." .. field,
            readValue = readValue or function() return db[field] end,
            writeValue = writeValue or function(value) db[field] = value end,
        })
    end
    group._timerBarFillModeOnly = opts.fillModeOnly == true
    if not isNew then
        -- 下拉菜单由对象池复用，但严格 TimerBar 与旧模块的 fill 值集合不同。
        -- 每次借用都必须覆盖菜单与当前值，不能保留上一次页面的项目或闭包语义。
        local fillMode = group._timerBarFillModeDropdown
        if not fillMode then
            error("CreateTimerBarGroup: pooled group is missing fillMode dropdown", 2)
        end
        fillMode._items = group._timerBarFillModeOnly and {
            { L["左到右填满"], "LTR_FILL" }, { L["左到右消退"], "LTR_FADE" },
            { L["右到左填满"], "RTL_FILL" }, { L["右到左消退"], "RTL_FADE" },
        } or {
            { L["左到右填满"], "LTR_FILL" }, { L["左到右消退"], "LTR_DRAIN" },
            { L["右到左填满"], "RTL_FILL" }, { L["右到左消退"], "RTL_DRAIN" },
        }
        fillMode._currentValue = db.fillMode
        SetDropdownDisplayText(fillMode, CompositeDropdownText(db.fillMode, fillMode._items) or L["请选择..."])
        AttachCompositeRelease(group)
        ReflowCompositeGroup(group, groupWidth, groupHeight)
        return group
    end
    local proxy = CreateCompositeProxy(group)
    db = proxy

    local function EmitUpdate() CompositeEmitUpdate(group) end
    local function GetTimerBarInputMetadata()
        local activeOpts = group._exCompositeOpts or {}
        local metadata = activeOpts._exWriteContext
        if metadata == nil then return nil end
        if type(metadata) ~= "table" or type(metadata.moduleKey) ~= "string" or metadata.moduleKey == ""
            or type(metadata.pathPrefix) ~= "string" or metadata.pathPrefix == "" then
            error("CreateTimerBarGroup requires Grid write context", 2)
        end
        local commitAPI = EXUI.CommitModuleValue
        if type(commitAPI) ~= "function" then
            error("CreateTimerBarGroup requires CommitModuleValue", 2)
        end
        return metadata.moduleKey, metadata.pathPrefix
    end
    local function CommitTimerBarValue(field, value, writeValue)
        local moduleKey, prefix = GetTimerBarInputMetadata()
        local Write = writeValue or function(nextValue) db[field] = nextValue end
        if moduleKey then
            return EXUI:CommitModuleValue({
                moduleKey = moduleKey, path = prefix .. "." .. field,
                readValue = function() return db[field] end, writeValue = Write,
            }, value)
        end
        Write(value)
        EmitUpdate()
        return true
    end
    local palette = {
        panel = { 0.094, 0.094, 0.106, 1 }, card = { 0.112, 0.112, 0.125, 1 },
        utility = { 0.106, 0.106, 0.118, 1 }, border = { 1, 1, 1, 0.10 },
        text = { 0.96, 0.96, 0.97, 1 }, value = { 0.204, 0.827, 0.599, 1 },
    }
    local flatBackdrop = {
        bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    }
    group:SetSize(groupWidth, groupHeight)
    group:SetBackdrop(flatBackdrop)
    group:SetBackdropColor(unpack(palette.panel))
    group:SetBackdropBorderColor(unpack(palette.border))

    local header = CreateFrame("Frame", nil, group)
    header:SetSize(groupWidth, 40); header:SetPoint("TOPLEFT")
    local title = EXUI:CreateVisualFontString(header, EXFONTFRAME, "GameFontNormalHuge")
    title:SetPoint("LEFT", 15, 0); title:SetText(group._exCompositeLabel); title:SetTextColor(unpack(palette.text))
    group._exCompositeTitle = title
    local accent = EXUI:CreateVisualTexture(header, EXBASEFRAME)
    accent:SetPoint("LEFT", 6, 0); accent:SetSize(3, 21); accent:SetColorTexture(unpack(palette.value))

    local content = CreateFrame("Frame", nil, group)
    content:SetSize(groupWidth, groupHeight - 40); content:SetPoint("TOPLEFT", 0, -40)
    local padding, gap, controlsGap = 15, 12, 18
    local controlWidth = math.min(416, math.max(364, math.floor(groupWidth * 0.40)))
    local metricsWidth = groupWidth - padding * 2 - controlsGap - controlWidth
    local itemWidth = math.floor((metricsWidth - gap) / 2)
    local col1, col2 = padding, padding + itemWidth + gap
    local row1, row2, row3 = -8, -76, -144
    local controlX = padding + metricsWidth + controlsGap

    local function CreateMetricCard(x, y)
        local card = CreateFrame("Frame", nil, content, "BackdropTemplate")
        card:SetPoint("TOPLEFT", x, y); card:SetSize(itemWidth, 60)
        card:SetBackdrop(flatBackdrop); card:SetBackdropColor(unpack(palette.card)); card:SetBackdropBorderColor(unpack(palette.border))
        return card
    end
    local widthCard, heightCard = CreateMetricCard(col1, row1), CreateMetricCard(col2, row1)
    local xCard, yCard = CreateMetricCard(col1, row2), CreateMetricCard(col2, row2)
    local colorCard, textureCard = CreateMetricCard(col1, row3), CreateMetricCard(col2, row3)
    local sliderWidth = itemWidth - 20
    local function AddSlider(card, titleText, field, min, max, step)
        local lifecycle, transaction
        local slider = EXUI:CreateSlider(card, sliderWidth, titleText, min, max, db[field], step, nil, {
            onBegin = function()
                transaction = CreateTimerBarNotifyFlowForValue(field)
                if transaction then transaction.onBegin(); return end
                lifecycle = CreateTimerBarNotifyFlow(field)
                if lifecycle and lifecycle.onBegin then lifecycle.onBegin() end
            end,
            onLive = function(value)
                if transaction then return transaction.onLive(value) end
                if lifecycle and lifecycle.onLive then return lifecycle.onLive(value) end
                db[field] = value
            end,
            onCommit = function(value)
                -- 输入框路径没有 onBegin；按提交当下的声明建立同一事务。
                if not transaction then transaction = CreateTimerBarNotifyFlowForValue(field) end
                if transaction then
                    local result = transaction.onCommit(value)
                    transaction = nil
                    return result
                end
                if lifecycle and lifecycle.onCommit then
                    local result = lifecycle.onCommit(value)
                    lifecycle = nil
                    return result
                end
                db[field] = value
                EmitUpdate()
            end,
        })
        slider:SetPoint("TOPLEFT", 10, -25)
        if slider.labelText then slider.labelText:SetTextColor(unpack(palette.text)) end
        if slider.ValueText then slider.ValueText:SetTextColor(unpack(palette.value)) end
        return RegisterCompositeControl(group, slider, field, "slider")
    end
    -- 边框/图标弹窗里的数值控件也必须遵守与主面板同一 live 合同：
    -- 拖动仅重套已物化视觉，松手才统一广播 DatabaseChanged。
    local function AddPopupSlider(parent, sliderWidth, titleText, field, min, max, step)
        local lifecycle, transaction
        local slider = EXUI:CreateSlider(parent, sliderWidth, titleText, min, max, db[field], step, nil, {
            onBegin = function()
                transaction = CreateTimerBarNotifyFlowForValue(field)
                if transaction then transaction.onBegin(); return end
                lifecycle = CreateTimerBarNotifyFlow(field)
                if lifecycle and lifecycle.onBegin then lifecycle.onBegin() end
            end,
            onLive = function(value)
                if transaction then return transaction.onLive(value) end
                if lifecycle and lifecycle.onLive then return lifecycle.onLive(value) end
                db[field] = value
            end,
            onCommit = function(value)
                -- 弹窗 Slider 的数字输入也必须走同一条事务。
                if not transaction then transaction = CreateTimerBarNotifyFlowForValue(field) end
                if transaction then
                    local result = transaction.onCommit(value)
                    transaction = nil
                    return result
                end
                if lifecycle and lifecycle.onCommit then
                    local result = lifecycle.onCommit(value)
                    lifecycle = nil
                    return result
                end
                db[field] = value
                EmitUpdate()
            end,
        })
        if slider.labelText then slider.labelText:SetTextColor(unpack(palette.text)) end
        if slider.ValueText then slider.ValueText:SetTextColor(unpack(palette.value)) end
        return slider
    end
    AddSlider(widthCard, L["宽度 (Width)"], "width", 50, 800, 1)
    AddSlider(heightCard, L["高度 (Height)"], "height", 8, 120, 1)
    AddSlider(xCard, L["X 轴偏移"], "x", -1000, 1000, 1)
    AddSlider(yCard, L["Y 轴偏移"], "y", -1000, 1000, 1)

    -- 第三行：两个半宽颜色按钮 + 一项 LSM 条体材质。
    local colorHalfWidth = math.floor((itemWidth - 30) / 2)
    local function CreateColorTransaction(field)
        return function()
            return CreateTimerBarNotifyFlowForValue(field,
                function()
                    return { r = db[field .. "R"], g = db[field .. "G"], b = db[field .. "B"], a = db[field .. "A"] }
                end,
                function(value)
                    db[field .. "R"], db[field .. "G"], db[field .. "B"], db[field .. "A"] = value.r, value.g, value.b, value.a
                end)
        end
    end
    local fgButton = EXUI:CreateColorButton(colorCard, L["前景"], db, "barColor", true, EmitUpdate,
        { _changeFlow = CreateColorTransaction("barColor") })
    fgButton:SetSize(colorHalfWidth, 36); fgButton:SetPoint("TOPLEFT", 10, -12)
    local bgButton = EXUI:CreateColorButton(colorCard, L["背景"], db, "barBgColor", true, EmitUpdate,
        { _changeFlow = CreateColorTransaction("barBgColor") })
    bgButton:SetSize(colorHalfWidth, 36); bgButton:SetPoint("TOPLEFT", 15 + colorHalfWidth, -12)
    local textureDrop = EXUI:CreateLSMTextureDropdown(textureCard, "statusbar", sliderWidth, L["LSM皮肤"], db.texture, function(value)
        CommitTimerBarValue("texture", value)
    end)
    textureDrop:SetPoint("TOPLEFT", 10, -26)

    local actionCard = CreateFrame("Frame", nil, content, "BackdropTemplate")
    actionCard:SetPoint("TOPLEFT", controlX, row1); actionCard:SetSize(controlWidth, 196)
    actionCard:SetBackdrop(flatBackdrop); actionCard:SetBackdropColor(unpack(palette.utility)); actionCard:SetBackdropBorderColor(1, 1, 1, 0.16)
    local function StyleCheck(check)
        check.label:SetTextColor(unpack(palette.text))
        if check.checkbox:GetCheckedTexture() then check.checkbox:GetCheckedTexture():SetVertexColor(unpack(palette.value)) end
    end
    local function ActionButton(text, y, callback)
        local button = CreateFrame("Button", nil, actionCard, "BackdropTemplate")
        button:SetSize(math.min(187, math.floor(controlWidth * 0.45)), 28)
        button:RegisterForClicks("LeftButtonUp")
        button:SetBackdrop(flatBackdrop)
        button:SetBackdropColor(0.06, 0.15, 0.12, 0.72)
        button:SetBackdropBorderColor(0.204, 0.827, 0.599, 0.22)

        local textLabel = EXUI:CreateVisualFontString(button, EXFONTFRAME, "GameFontHighlightSmall")
        textLabel:SetPoint("CENTER", 0, -1)
        textLabel:SetText(text)
        textLabel:SetTextColor(unpack(palette.value))

        button:SetScript("OnEnter", function()
            button:SetBackdropColor(0.07, 0.20, 0.15, 0.86)
            button:SetBackdropBorderColor(0.204, 0.827, 0.599, 0.58)
            textLabel:SetTextColor(0.75, 0.96, 0.86, 1)
        end)
        button:SetScript("OnLeave", function()
            button:SetBackdropColor(0.06, 0.15, 0.12, 0.72)
            button:SetBackdropBorderColor(0.204, 0.827, 0.599, 0.22)
            textLabel:SetTextColor(unpack(palette.value))
        end)
        button:SetScript("OnClick", callback)
        button:SetPoint("TOPRIGHT", -10, y)
        return button
    end

    local popupList = {}
    local function CreatePopup(titleText, popupWidth, popupHeight)
        local popup = CreateCompositePopupHost(group, popupWidth, popupHeight)
        popup:SetBackdrop(flatBackdrop); popup:SetBackdropColor(unpack(palette.panel)); popup:SetBackdropBorderColor(unpack(palette.border)); popup:Hide()
        local popupTitle = EXUI:CreateVisualFontString(popup, EXFONTFRAME, "GameFontHighlight")
        popupTitle:SetPoint("TOPLEFT", 13, -9); popupTitle:SetText(titleText); popupTitle:SetTextColor(unpack(palette.text))
        local close = EXUI:CreateButton(popup, 28, 24, "×", function() popup:Hide() end)
        close:SetPoint("TOPRIGHT", -7, -4)
        popupList[#popupList + 1] = popup
        return popup
    end
    local function TogglePopup(popup, anchor)
        local show = not popup:IsShown()
        for _, other in ipairs(popupList) do other:Hide() end
        if show then popup:ClearAllPoints(); popup:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -6); popup:Show() end
    end

    local borderPopup = CreatePopup(L["边框设置"], 540, 166)
    local borderTexture = EXUI:CreateLSMTextureDropdown(borderPopup, "border", 245, L["边框材质"], db.borderTexture, function(value)
        CommitTimerBarValue("borderTexture", value)
    end)
    borderTexture:SetPoint("TOPLEFT", 14, -46)
    local borderColor = EXUI:CreateColorButton(borderPopup, L["边框颜色"], db, "borderColor", true, EmitUpdate,
        { _changeFlow = CreateColorTransaction("borderColor") })
    borderColor:SetPoint("TOPLEFT", 280, -42)
    local borderSize = AddPopupSlider(borderPopup, 245, L["边框粗细"], "borderSize", 0, 20, 0.1)
    borderSize:SetPoint("TOPLEFT", 14, -112)
    local borderPad = AddPopupSlider(borderPopup, 245, L["边框间距 (Padding)"], "borderPadding", -10, 10, 0.1)
    borderPad:SetPoint("TOPLEFT", 280, -112)

    local iconPopup = CreatePopup(L["图标设置"], 700, 306)
    local iconColumnWidth, iconColumn2 = 320, 362
    local iconSides = { { L["左侧"], "LEFT" }, { L["中间"], "CENTER" }, { L["右侧"], "RIGHT" } }
    local iconSide = EXUI:CreateDropdown(iconPopup, iconColumnWidth, L["图标位置"], iconSides, db.iconSide, function(value)
        CommitTimerBarValue("iconSide", value)
    end)
    iconSide:SetPoint("TOPLEFT", 14, -46)
    -- 坐标最终由 Widget 按物理像素对齐；和条/文字/材质的其它位置控件一致，
    -- 必须使用整数步进。0.1 会把 -200..200 扩成 4,000 个原生 Slider 档位，
    -- 但不会产生额外可见位置，反而只让这两个拖动控件异常迟滞。
    local iconOffsetX = AddPopupSlider(iconPopup, iconColumnWidth, L["图标 X 轴偏移"], "iconOffsetX", iconOffsetMin, iconOffsetMax, 1)
    iconOffsetX:SetPoint("TOPLEFT", iconColumn2, -46)
    local iconWidth = AddPopupSlider(iconPopup, iconColumnWidth, L["图标宽度"], "iconWidth", 8, 160, 1)
    iconWidth:SetPoint("TOPLEFT", 14, -100)
    local iconHeight = AddPopupSlider(iconPopup, iconColumnWidth, L["图标高度"], "iconHeight", 8, 160, 1)
    iconHeight:SetPoint("TOPLEFT", iconColumn2, -100)
    local iconOffsetY = AddPopupSlider(iconPopup, iconColumnWidth, L["图标 Y 轴偏移"], "iconOffsetY", iconOffsetMin, iconOffsetMax, 1)
    iconOffsetY:SetPoint("TOPLEFT", 14, -154)
    local showIconBorder = EXUI:CreateCheckbox(iconPopup, L["显示图标边框"], db.showIconBorder, function(value)
        CommitTimerBarValue("showIconBorder", value)
    end)
    showIconBorder:SetPoint("TOPLEFT", iconColumn2, -154); StyleCheck(showIconBorder)
    local iconBorderTexture = EXUI:CreateLSMTextureDropdown(iconPopup, "border", iconColumnWidth, L["图标边框材质"], db.iconBorderTexture, function(value)
        CommitTimerBarValue("iconBorderTexture", value)
    end)
    iconBorderTexture:SetPoint("TOPLEFT", 14, -208)
    local iconBorderColor = EXUI:CreateColorButton(iconPopup, L["图标边框颜色"], db, "iconBorderColor", true, EmitUpdate,
        { _changeFlow = CreateColorTransaction("iconBorderColor") })
    iconBorderColor:SetPoint("TOPLEFT", iconColumn2, -204)
    local iconBorderSize = AddPopupSlider(iconPopup, iconColumnWidth, L["图标边框粗细"], "iconBorderSize", 0, 20, 0.1)
    iconBorderSize:SetPoint("TOPLEFT", 14, -262)
    local iconBorderPad = AddPopupSlider(iconPopup, iconColumnWidth, L["图标边框间距"], "iconBorderPadding", -10, 10, 0.1)
    iconBorderPad:SetPoint("TOPLEFT", iconColumn2, -262)

    local fillPopup = CreatePopup(L["填充设置"], 540, 126)
    local fillOptions = opts.fillModeOnly == true and {
        { L["左到右填满"], "LTR_FILL" }, { L["左到右消退"], "LTR_FADE" },
        { L["右到左填满"], "RTL_FILL" }, { L["右到左消退"], "RTL_FADE" },
    } or {
        { L["左到右填满"], "LTR_FILL" }, { L["左到右消退"], "LTR_DRAIN" },
        { L["右到左填满"], "RTL_FILL" }, { L["右到左消退"], "RTL_DRAIN" },
    }
    local fillMode = EXUI:CreateDropdown(fillPopup, 510, L["填充方式"], fillOptions, db.fillMode, function(value)
        local function WriteFillMode(nextValue)
            db.fillMode = nextValue
            if group._timerBarFillModeOnly == true then return end
            if nextValue == "LTR_FILL" then db.fillDirection, db.progressMode = "LEFT_TO_RIGHT", "ELAPSED"
            elseif nextValue == "LTR_DRAIN" then db.fillDirection, db.progressMode = "RIGHT_TO_LEFT", "REMAINING"
            elseif nextValue == "RTL_FILL" then db.fillDirection, db.progressMode = "RIGHT_TO_LEFT", "ELAPSED"
            else db.fillDirection, db.progressMode = "LEFT_TO_RIGHT", "REMAINING" end
        end
        if group._timerBarFillModeOnly == true then
            CommitTimerBarValue("fillMode", value, WriteFillMode)
            return
        end
        CommitTimerBarValue("fillMode", value, WriteFillMode)
    end)
    fillMode:SetPoint("TOPLEFT", 14, -46)
    group._timerBarFillModeDropdown = fillMode

    local showIcon = EXUI:CreateCheckbox(actionCard, L["显示图标"], db.showIcon, function(value)
        CommitTimerBarValue("showIcon", value)
    end)
    showIcon:SetPoint("TOPLEFT", 12, -4); showIcon:SetSize(150, 28); StyleCheck(showIcon)
    local iconButton = ActionButton(L["图标设置"], -4, function(self) TogglePopup(iconPopup, self) end)

    local showBorder = EXUI:CreateCheckbox(actionCard, L["显示边框"], db.showBorder, function(value)
        CommitTimerBarValue("showBorder", value)
    end)
    showBorder:SetPoint("TOPLEFT", 12, -72); showBorder:SetSize(150, 28); StyleCheck(showBorder)
    local borderButton = ActionButton(L["边框设置"], -72, function(self) TogglePopup(borderPopup, self) end)

    local fillLabel = EXUI:CreateVisualFontString(actionCard, EXFONTFRAME, "GameFontHighlight")
    -- LEFT 锚点的 Y 偏移从垂直中线计算，会把文字推到卡片外；必须以 TOPLEFT 定位。
    fillLabel:SetPoint("TOPLEFT", actionCard, "TOPLEFT", 48, -140); fillLabel:SetText(L["填充方式"]); fillLabel:SetTextColor(unpack(palette.text))
    local fillButton = ActionButton(L["填充设置"], -140, function(self) TogglePopup(fillPopup, self) end)

    if opts.applicationBar == true then
        -- ApplicationBar 的进度和法术图标由原生 Aura 绑定决定；这些控制项写入数据却
        -- 不会影响原生条，故不向用户显示。
        showIcon:Hide()
        iconButton:Hide()
        fillLabel:Hide()
        fillButton:Hide()
        iconPopup:Hide()
        fillPopup:Hide()
        actionCard:SetHeight(128)
    end

    RegisterCompositeControl(group, fgButton, "barColor", "color")
    RegisterCompositeControl(group, bgButton, "barBgColor", "color")
    RegisterCompositeControl(group, textureDrop, "texture", "dropdown")
    RegisterCompositeControl(group, borderTexture, "borderTexture", "dropdown")
    RegisterCompositeControl(group, borderColor, "borderColor", "color")
    RegisterCompositeControl(group, borderSize, "borderSize", "slider")
    RegisterCompositeControl(group, borderPad, "borderPadding", "slider")
    RegisterCompositeControl(group, iconSide, "iconSide", "dropdown")
    RegisterCompositeControl(group, iconOffsetX, "iconOffsetX", "slider")
    RegisterCompositeControl(group, iconWidth, "iconWidth", "slider")
    RegisterCompositeControl(group, iconHeight, "iconHeight", "slider")
    RegisterCompositeControl(group, iconOffsetY, "iconOffsetY", "slider")
    RegisterCompositeControl(group, showIconBorder, "showIconBorder", "check")
    RegisterCompositeControl(group, iconBorderTexture, "iconBorderTexture", "dropdown")
    RegisterCompositeControl(group, iconBorderColor, "iconBorderColor", "color")
    RegisterCompositeControl(group, iconBorderSize, "iconBorderSize", "slider")
    RegisterCompositeControl(group, iconBorderPad, "iconBorderPadding", "slider")
    RegisterCompositeControl(group, fillMode, "fillMode", "dropdown")
    RegisterCompositeControl(group, showIcon, "showIcon", "check")
    RegisterCompositeControl(group, showBorder, "showBorder", "check")
    group._exCompositePopups = popupList
    group._timerBarDb = proxy
    group._exCompositeReflow = function(self, nextWidth, nextHeight)
        local nextControlWidth = math.min(416, math.max(364, math.floor(nextWidth * 0.40)))
        local nextMetricsWidth = nextWidth - padding * 2 - controlsGap - nextControlWidth
        local nextItemWidth = math.floor((nextMetricsWidth - gap) / 2)
        local nextCol2 = padding + nextItemWidth + gap
        local nextControlX = padding + nextMetricsWidth + controlsGap
        local nextSliderWidth = nextItemWidth - 20
        local nextColorHalfWidth = math.floor((nextItemWidth - 30) / 2)

        header:SetSize(nextWidth, 40)
        content:SetSize(nextWidth, nextHeight - 40)
        for _, card in ipairs({ widthCard, heightCard, xCard, yCard, colorCard, textureCard }) do card:SetSize(nextItemWidth, 60) end
        widthCard:ClearAllPoints(); widthCard:SetPoint("TOPLEFT", content, "TOPLEFT", col1, row1)
        heightCard:ClearAllPoints(); heightCard:SetPoint("TOPLEFT", content, "TOPLEFT", nextCol2, row1)
        xCard:ClearAllPoints(); xCard:SetPoint("TOPLEFT", content, "TOPLEFT", col1, row2)
        yCard:ClearAllPoints(); yCard:SetPoint("TOPLEFT", content, "TOPLEFT", nextCol2, row2)
        colorCard:ClearAllPoints(); colorCard:SetPoint("TOPLEFT", content, "TOPLEFT", col1, row3)
        textureCard:ClearAllPoints(); textureCard:SetPoint("TOPLEFT", content, "TOPLEFT", nextCol2, row3)
        for _, entry in ipairs(self._exCompositeControls or {}) do
            if entry.kind == "slider" and entry.control:GetParent() ~= borderPopup and entry.control:GetParent() ~= iconPopup then
                entry.control:SetWidth(nextSliderWidth)
            end
        end
        fgButton:SetSize(nextColorHalfWidth, 36)
        bgButton:SetSize(nextColorHalfWidth, 36)
        bgButton:ClearAllPoints(); bgButton:SetPoint("TOPLEFT", colorCard, "TOPLEFT", 15 + nextColorHalfWidth, -12)
        textureDrop:SetWidth(nextSliderWidth)
        actionCard:ClearAllPoints(); actionCard:SetPoint("TOPLEFT", content, "TOPLEFT", nextControlX, row1)
        actionCard:SetWidth(nextControlWidth)
        local nextActionButtonWidth = math.min(187, math.floor(nextControlWidth * 0.45))
        iconButton:SetWidth(nextActionButtonWidth); borderButton:SetWidth(nextActionButtonWidth); fillButton:SetWidth(nextActionButtonWidth)
    end
    group:_exCompositeReflow(groupWidth, groupHeight)
    AttachCompositeRelease(group)
    return group
end

-- =========================================================
-- 19. Glow 设置组（Core 原生动画引擎）
-- 旧版 CreateGlowSettings 对应 LibCustomGlow 参数；保留别名仅作代码参考，
-- 公开入口改为 EXUI Glow 的 Pulse / Translation 线条 / Proc 三种样式。
-- =========================================================
EXUI.CreateGlowSettingsLegacy = EXUI.CreateGlowSettings

function EXUI:CreateGlowSettings(parent, width, label, db, key, onUpdate)
    db = type(db) == "table" and db or {}
    key = key or "glow"

    local legacyStyles = {
        ["Action Button Glow"] = "PULSE",
        ["Pixel Glow"] = "EDGE_FLOW",
        ["Autocast Shine"] = "EDGE_FLOW",
        ["Proc Glow"] = "PROC_FLIPBOOK",
        ["Proc Alt Glow"] = "PROC_FLIPBOOK",
    }
    local function SetDefault(suffix, value)
        local field = key .. suffix
        if db[field] == nil then db[field] = value end
    end
    SetDefault("Enabled", true)
    SetDefault("Style", "EDGE_FLOW")
    SetDefault("Frequency", 1)
    SetDefault("Lines", 1)
    SetDefault("Length", 32)
    SetDefault("Thickness", 2)
    SetDefault("Direction", "CLOCKWISE")
    SetDefault("Scale", 1)
    SetDefault("Offset", 3)
    SetDefault("ColorR", 1)
    SetDefault("ColorG", 0.82)
    SetDefault("ColorB", 0.20)
    SetDefault("ColorA", 1)
    db[key .. "Style"] = legacyStyles[db[key .. "Style"]] or db[key .. "Style"]

    local groupWidth, groupHeight = width or 750, 292
    local group = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    group:SetSize(groupWidth, groupHeight)
    -- 标准 Slider 合同元数据：只暴露既有控件与其真实 DB 路径，
    -- 不改变视觉、写入时机或原有回调。
    group._exStandardSliderControls = {}
    group._exStandardSliderDB = db
    group:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    group:SetBackdropColor(0.094, 0.094, 0.106, 1)
    group:SetBackdropBorderColor(1, 1, 1, 0.10)

    local titleAccent = EXUI:CreateVisualTexture(group, EXBASEFRAME)
    titleAccent:SetPoint("TOPLEFT", 7, -12)
    titleAccent:SetSize(3, 21)
    titleAccent:SetColorTexture(0.204, 0.827, 0.599, 1)
    local title = EXUI:CreateVisualFontString(group, EXFONTFRAME, "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", 16, -8)
    title:SetText(label or L["发光设置"])
    title:SetTextColor(0.96, 0.96, 0.97, 1)

    local content = CreateFrame("Frame", nil, group)
    content:SetPoint("TOPLEFT", 0, -42)
    content:SetSize(groupWidth, groupHeight - 42)
    local padding, gap = 15, 16
    local itemWidth = math.floor((groupWidth - padding * 2 - gap * 2) / 3)
    local col1, col2, col3 = padding, padding + itemWidth + gap, padding + (itemWidth + gap) * 2

    local function EmitUpdate()
        if onUpdate then onUpdate(db) end
    end
    local function MakeSlider(text, suffix, min, max, step, x, y)
        local slider = EXUI:CreateSlider(content, itemWidth, text, min, max, db[key .. suffix], step, nil, function(value)
            db[key .. suffix] = value
            EmitUpdate()
        end)
        slider:SetPoint("TOPLEFT", x, y)
        table.insert(group._exStandardSliderControls, {
            control = slider,
            path = key .. suffix,
        })
        return slider
    end

    local enabled = EXUI:CreateCheckbox(content, L["启用发光"], db[key .. "Enabled"], function(value)
        db[key .. "Enabled"] = value
        EmitUpdate()
    end)
    enabled:SetPoint("TOPLEFT", col2, -8)
    enabled:SetSize(itemWidth, 28)

    local styles = {
        { L["呼吸发光（Alpha + Scale）"], "PULSE" },
        { L["边框线条流光（原生 Translation）"], "EDGE_FLOW" },
        { L["触发光环（原生 Proc）"], "PROC_FLIPBOOK" },
    }
    local styleDrop = EXUI:CreateDropdown(content, itemWidth, L["发光样式"], styles, db[key .. "Style"], function(value)
        db[key .. "Style"] = value
        group:RefreshLayout()
        EmitUpdate()
    end)
    styleDrop:SetPoint("TOPLEFT", col3, -14)
    local color = EXUI:CreateColorButton(content, L["发光颜色"], db, key .. "Color", true, EmitUpdate)
    color:SetPoint("TOPLEFT", col1, -14)

    local lines = MakeSlider(L["数量"], "Lines", 1, 36, 1, col1, -76)
    local length = MakeSlider(L["长度"], "Length", 8, 120, 1, col2, -76)
    local thickness = MakeSlider(L["粗度"], "Thickness", 1, 20, 0.5, col3, -76)
    local frequency = MakeSlider(L["速度"], "Frequency", 0.1, 5, 0.1, col1, -138)
    local scale = MakeSlider(L["大小倍率"], "Scale", 0.25, 3, 0.05, col2, -138)
    local offset = MakeSlider(L["间距（负值向内）"], "Offset", -20, 50, 1, col2, -138)
    local directionItems = {
        { L["顺时针"], "CLOCKWISE" },
        { L["逆时针"], "COUNTERCLOCKWISE" },
    }
    local direction = EXUI:CreateDropdown(content, itemWidth, L["方向"], directionItems, db[key .. "Direction"], function(value)
        db[key .. "Direction"] = value
        EmitUpdate()
    end)
    direction:SetPoint("TOPLEFT", col3, -144)
    local info = EXUI:CreateVisualFontString(content, EXFONTFRAME, "GameFontNormalSmall")
    info:SetPoint("TOPLEFT", col1, -204)
    info:SetPoint("TOPRIGHT", -15, -204)
    info:SetJustifyH("LEFT")
    info:SetTextColor(0.62, 0.68, 0.72, 1)

    function group:RefreshLayout()
        local style = db[key .. "Style"]
        local isTrail = style == "EDGE_FLOW"
        local function Place(control, shown, x, y)
            control:ClearAllPoints()
            control:SetShown(shown)
            if shown then control:SetPoint("TOPLEFT", x, y) end
        end

        -- 线条样式有线条专属参数；Pulse 与 Proc 共用速度、大小、外扩边距。
        Place(lines, isTrail, col1, -76)
        Place(length, isTrail, col2, -76)
        Place(thickness, isTrail, col3, -76)
        Place(frequency, true, col1, isTrail and -138 or -76)
        Place(scale, not isTrail, col2, -76)
        Place(offset, true, isTrail and col2 or col3, isTrail and -138 or -76)
        direction:ClearAllPoints()
        direction:SetShown(isTrail)
        if isTrail then direction:SetPoint("TOPLEFT", col3, -144) end
        if isTrail then
            info:SetText(L["数量 = 同时环绕的线条数；间距可为负，负值让线条向图标内部收。四边移动完全由原生 Translation 处理。"])
        elseif style == "PROC_FLIPBOOK" then
            info:SetText(L["使用暴雪原生 Proc FlipBook；速度同时控制起手段与循环段，大小与外扩边距控制光环范围。"])
        else
            info:SetText(L["使用 Alpha + Scale 原生循环；速度控制呼吸节奏，大小与外扩边距控制发光范围。"])
        end
    end
    group:RefreshLayout()
    group._glowDb = db
    return group
end

-- =========================================================
-- 20. Widget 排列设置组
-- 只管理同一规则内多个 Widget 的增长方向、间距、最大显示数量与可选换行方向。
-- 整体 X/Y 属于模块 AnchorController，不能放在这里。
-- =========================================================
function EXUI:CreateWidgetLayoutGroup(parent, width, label, db, key, onUpdate, opts)
    opts = type(opts) == "table" and opts or {}
    if key and type(db) == "table" then
        db[key] = type(db[key]) == "table" and db[key] or {}
        db = db[key]
    end
    db = type(db) == "table" and db or {}
    local allowedDirections = type(opts.allowedDirections) == "table" and opts.allowedDirections or {
        "RIGHT", "LEFT", "DOWN", "UP", "CENTER_HORIZONTAL", "CENTER_VERTICAL",
    }
    local defaultDirection = allowedDirections[1] or "RIGHT"
    local wrapDirections = type(opts.wrapDirections) == "table" and opts.wrapDirections or {
        "DOWN", "UP",
    }
    local defaultWrapDirection = tostring(opts.defaultWrapDirection or wrapDirections[1] or "DOWN")
    local maxVisibleMin = math.max(1, tonumber(opts.maxVisibleMin) or 1)
    local maxVisibleMax = math.max(maxVisibleMin, tonumber(opts.maxVisibleMax) or 40)
    local defaultMaxVisible = tonumber(opts.defaultMaxVisible) or 8
    defaultMaxVisible = math.max(maxVisibleMin, math.min(defaultMaxVisible, maxVisibleMax))
    if db.direction == nil then db.direction = defaultDirection end
    if db.spacing == nil then db.spacing = 4 end
    if db.maxVisible == nil then db.maxVisible = defaultMaxVisible end
    if db.maxPerRow == nil then db.maxPerRow = 8 end
    if db.wrapDirection == nil then db.wrapDirection = defaultWrapDirection end

    local includeMaxPerRow = opts.includeMaxPerRow ~= false
    local includeWrapDirection = opts.includeWrapDirection == true
    local groupWidth = width or 760
    -- Slider 的数字输入框位于轨道下方；卡片必须把它完整纳入自身高度。
    -- 旧高度 72/118 会让最后一排输入框伸进下一张 Grid 卡片：画面可见，
    -- 但鼠标命中被下一张卡接管，于是只能拖轨道、不能直接点数值输入。
    local groupHeight = (includeMaxPerRow or includeWrapDirection) and 134 or 88
    -- 二维换行卡有额外的下拉控件，必须使用已注册的独立宿主池；
    -- 不能让它和普通单轴卡复用，也不能接受任意外部池名。
    local poolType = includeWrapDirection and "CompositeWidgetLayoutGroupWithWrap" or "CompositeWidgetLayoutGroup"
    local group, isNew = AcquireCompositeGroup(poolType, parent)
    group._exCompositeLabel = label or L["排序"]
    BindCompositeGroup(group, db, onUpdate, opts)
    if not isNew then
        AttachCompositeRelease(group)
        local maxVisible = group._exWidgetLayoutMaxVisible
        if maxVisible then
            maxVisible:SetMinMaxValues(maxVisibleMin, maxVisibleMax)
            local value = tonumber(db.maxVisible) or defaultMaxVisible
            value = math.max(maxVisibleMin, math.min(value, maxVisibleMax))
            db.maxVisible = value
            maxVisible:SetValue(value)
        end
        ReflowCompositeGroup(group, groupWidth, groupHeight)
        if group._exWidgetLayoutHint then group._exWidgetLayoutHint:Hide() end
        return group
    end
    local proxy = CreateCompositeProxy(group)
    db = proxy
    group:SetSize(groupWidth, groupHeight)
    group:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    group:SetBackdropColor(0.094, 0.094, 0.106, 1)
    group:SetBackdropBorderColor(1, 1, 1, 0.10)

    local accent = EXUI:CreateVisualTexture(group, EXBASEFRAME)
    accent:SetPoint("TOPLEFT", 7, -11)
    accent:SetSize(3, 20)
    accent:SetColorTexture(0.204, 0.827, 0.599, 1)

    local title = EXUI:CreateVisualFontString(group, EXFONTFRAME, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -8)
    title:SetText(group._exCompositeLabel)
    group._exCompositeTitle = title

    local function EmitUpdate() CompositeEmitUpdate(group) end

    -- Layout 卡片本身会从对象池复用；每次输入都必须从当前宿主读取
    -- Grid 写入上下文，不能捕获第一次（通常是 TimerBar）创建时的 moduleKey。
    local function CreateLayoutInputTransaction(field)
        local activeOpts = group._exCompositeOpts or {}
        local metadata = activeOpts._exWriteContext
        if metadata == nil then return nil end
        if type(metadata) ~= "table" or type(metadata.moduleKey) ~= "string" or metadata.moduleKey == "" then
            error("CreateWidgetLayoutGroup requires Grid write context", 2)
        end
        if type(EXUI.CreateModuleNotifyFlow) ~= "function" then
            error("CreateWidgetLayoutGroup requires CreateModuleNotifyFlow", 2)
        end
        local prefix = metadata.pathPrefix
        if prefix ~= nil and type(prefix) ~= "string" then
            error("CreateWidgetLayoutGroup Grid write context pathPrefix must be string or nil", 2)
        end
        local path = type(prefix) == "string" and prefix ~= "" and (prefix .. "." .. field) or field
        return EXUI:CreateModuleNotifyFlow({
            moduleKey = metadata.moduleKey,
            path = path,
            readValue = function() return group._widgetLayoutDb[field] end,
            writeValue = function(value) group._widgetLayoutDb[field] = value end,
        })
    end

    local function CommitLayoutValue(field, value)
        local transaction = CreateLayoutInputTransaction(field)
        if transaction and transaction.onCommit then return transaction.onCommit(value) end
        group._widgetLayoutDb[field] = value
        EmitUpdate()
        return true
    end

    local directionLabels = {
        RIGHT = L["向右"], LEFT = L["向左"], DOWN = L["向下"], UP = L["向上"],
        CENTER_HORIZONTAL = L["左右居中"], CENTER_VERTICAL = L["上下居中"],
    }
    local directionItems = {}
    for _, directionKey in ipairs(allowedDirections) do
        directionItems[#directionItems + 1] = { directionLabels[directionKey] or tostring(directionKey), directionKey }
    end
    local direction = EXUI:CreateDropdown(group, math.min(220, groupWidth - 40), L["增长方向"], directionItems, db.direction, function(value)
        CommitLayoutValue("direction", value)
    end)
    direction:SetPoint("TOPLEFT", 16, -42)
    RegisterCompositeControl(group, direction, "direction", "dropdown")

    local spacing = EXUI:CreateSlider(group, math.min(180, math.max(120, groupWidth * 0.24)), L["间距"], -10, 20,
        tonumber(db.spacing) or 4, 0.1, nil, CreateLayoutInputTransaction("spacing") or function(value)
            db.spacing = value
            EmitUpdate()
        end)
    spacing:SetPoint("TOPLEFT", math.min(255, groupWidth * 0.36), -46)
    RegisterCompositeControl(group, spacing, "spacing", "slider")

    local maxVisible = EXUI:CreateSlider(group, math.min(180, math.max(120, groupWidth * 0.24)), L["最大显示"], maxVisibleMin, maxVisibleMax,
        tonumber(db.maxVisible) or defaultMaxVisible, 1, nil, CreateLayoutInputTransaction("maxVisible") or function(value)
            db.maxVisible = value
            EmitUpdate()
        end)
    maxVisible:SetPoint("TOPLEFT", math.min(470, groupWidth * 0.64), -46)
    RegisterCompositeControl(group, maxVisible, "maxVisible", "slider")
    group._exWidgetLayoutMaxVisible = maxVisible

    local maxPerRow
    if includeMaxPerRow then
        maxPerRow = EXUI:CreateSlider(group, math.min(180, math.max(120, groupWidth * 0.24)), L["每行最多"], 1, 40,
            tonumber(db.maxPerRow) or 8, 1, nil, CreateLayoutInputTransaction("maxPerRow") or function(value)
                db.maxPerRow = value
                EmitUpdate()
            end)
        maxPerRow:SetPoint("TOPLEFT", 16, -92)
        RegisterCompositeControl(group, maxPerRow, "maxPerRow", "slider")
    end

    local wrapDirection
    if includeWrapDirection then
        local wrapItems = {}
        for _, directionKey in ipairs(wrapDirections) do
            wrapItems[#wrapItems + 1] = { directionLabels[directionKey] or tostring(directionKey), directionKey }
        end
        wrapDirection = EXUI:CreateDropdown(group, math.min(180, math.max(120, groupWidth * 0.24)), L["换行方向"], wrapItems,
            db.wrapDirection, function(value)
                db.wrapDirection = value
                EmitUpdate()
            end)
        wrapDirection:SetPoint("TOPLEFT", math.min(255, groupWidth * 0.36), -88)
        RegisterCompositeControl(group, wrapDirection, "wrapDirection", "dropdown")
    end

    group._widgetLayoutDb = proxy
    group._exCompositeConfigure = function(self)
        local activeOpts = self._exCompositeOpts or {}
        local activeDirections = type(activeOpts.allowedDirections) == "table" and activeOpts.allowedDirections or {
            "RIGHT", "LEFT", "DOWN", "UP", "CENTER_HORIZONTAL", "CENTER_VERTICAL",
        }
        local activeItems = {}
        for _, directionKey in ipairs(activeDirections) do
            activeItems[#activeItems + 1] = { directionLabels[directionKey] or tostring(directionKey), directionKey }
        end
        direction._items = activeItems
        direction._currentValue = self._widgetLayoutDb.direction
        direction._onSelect = function(value) CommitLayoutValue("direction", value) end
        SetDropdownDisplayText(direction, CompositeDropdownText(direction._currentValue, activeItems) or L["请选择..."])

        local function RebindSlider(control, field)
            -- SetLifecycleCallbacks only replaces onValueChanged when given a
            -- function, so explicitly clear the fallback callback from a
            -- possible no-context first creation.
            control._onValueChanged = nil
            control:SetLifecycleCallbacks(CreateLayoutInputTransaction(field) or {})
        end
        RebindSlider(spacing, "spacing")
        RebindSlider(maxVisible, "maxVisible")
        if maxPerRow then RebindSlider(maxPerRow, "maxPerRow") end
    end
    group:_exCompositeConfigure()
    group._exCompositeReflow = function(self, nextWidth, nextHeight)
        local firstWidth = math.min(220, nextWidth - 40)
        local metricWidth = math.min(180, math.max(120, nextWidth * 0.24))
        direction:SetWidth(firstWidth)
        direction:ClearAllPoints(); direction:SetPoint("TOPLEFT", self, "TOPLEFT", 16, -42)
        spacing:SetWidth(metricWidth)
        spacing:ClearAllPoints(); spacing:SetPoint("TOPLEFT", self, "TOPLEFT", math.min(255, nextWidth * 0.36), -46)
        maxVisible:SetWidth(metricWidth)
        maxVisible:ClearAllPoints(); maxVisible:SetPoint("TOPLEFT", self, "TOPLEFT", math.min(470, nextWidth * 0.64), -46)
        if maxPerRow then
            maxPerRow:SetWidth(metricWidth)
            maxPerRow:ClearAllPoints(); maxPerRow:SetPoint("TOPLEFT", self, "TOPLEFT", 16, -92)
        end
        if wrapDirection then
            wrapDirection:SetWidth(metricWidth)
            wrapDirection:ClearAllPoints(); wrapDirection:SetPoint("TOPLEFT", self, "TOPLEFT", math.min(255, nextWidth * 0.36), -88)
        end
    end
    group:_exCompositeReflow(groupWidth, groupHeight)
    AttachCompositeRelease(group)
    return group
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

    -- 模块声明 fixedLayout 时使用固定的逻辑网格；不声明的历史调用者继续走
    -- 下方原有动态 Flow。逻辑尺寸只在这里按实际 groupWidth 转为物理像素，
    -- 让 Grid measure 与复合控件重排始终共享同一份高度合同。
    if type(opts.fixedLayout) == "table" then
        local fixed = opts.fixedLayout
        local logicalWidth = math.max(1, tonumber(fixed.logicalWidth) or 197)
        local controlW = math.max(1, tonumber(fixed.controlW) or 40)
        local controlH = math.max(1, tonumber(fixed.controlH) or 6)
        local slotX = type(fixed.slotX) == "table" and fixed.slotX or { 5, 55, 105, 155 }
        local firstY = tonumber(fixed.firstY) or 5
        local rowStep = math.max(controlH, tonumber(fixed.rowStep) or 12)
        local headerLogical = math.max(1, tonumber(fixed.headerH) or 6)
        local cardTopLogical = math.max(0, tonumber(fixed.cardTopInset) or 1)
        local cardBottomLogical = math.max(0, tonumber(fixed.cardBottomInset) or 5)
        local scale = groupWidth / logicalWidth
        -- 控件框的逻辑几何保持 40×6；但它们的 WoW 模板可见区域是固定像素，
        -- 例如 checkbox=28、color=36，slider 还包含标题、轨道和数值输入框。
        -- 因此测量时逐行记录实际可见底边，绝不能只用 6×scale 截断末行。
        local visibleBottomByType = {
            checkbox = 11 + 28,
            color = 14 + 36,
            slider = 25 + 20 + 3 + 20,
            dropdown = 25 + 30,
            lsm_background = 25 + 30,
            lsm_border = 25 + 30,
            lsm_texture = 25 + 30,
            input = 16 + 28,
            button = 16 + 28,
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
            headerHeight = headerLogical * scale,
            cardInsetX = 0,
            cardInsetY = cardTopLogical * scale,
            cardBottomInset = cardBottomLogical * scale,
            rowVisibleBottoms = rowVisibleBottoms,
            cardHeight = cardHeight,
            height = math.max(1, headerLogical * scale + cardTopLogical * scale
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
        headerHeight = 40,
        cardInsetX = padding,
        cardInsetY = 8,
        cardBottomInset = 8,
        -- 保留原来的外框总高度基线；紧凑首行只把后续行上移，留下底部安全
        -- 留白，避免 slider 的数值输入框贴住外框。
        height = math.max(1, 108 + (rows - 1) * rowStep + heightOffset),
    }
end

function EXUI:CreateModuleCommonSettingsGroup(parent, width, label, db, key, onUpdate, opts)
    opts = type(opts) == "table" and opts or {}
    if key and opts.bindRoot ~= true and type(db) == "table" then
        db[key] = type(db[key]) == "table" and db[key] or {}
        db = db[key]
    end
    db = type(db) == "table" and db or {}
    local groupWidth = width or 760
    local flow = self:BuildModuleCommonSettingsFlow(groupWidth, opts)
    local groupHeight = flow.height
    local group, isNew = AcquireCompositeGroup(opts.poolType or "CompositeModuleCommonSettingsGroup", parent)
    -- ModuleCommon 的根宿主是唯一可见的面板底色与边界。必须在每次从池中借用时
    -- 重套，避免上一轮清理后整个“模块通用设置”面板变成透明；内部 settingsCard
    -- 和每个 field card 都只定位，绝不绘制第二层黑框。
    ApplyCompositeGroupSurface(group,
        0.094, 0.094, 0.106, 1,
        1, 1, 1, 0.10)
    group._exCompositeLabel = label or L["模块通用设置"]
    -- modulecommonsettings 的 fields 是模块声明的动态结构，不能像字体/计时条/图标
    -- 等固定结构组那样整树复用。先归还上一轮的子控件，再按本轮 fields 建立；外壳
    -- 仍是 CompositeHost 池，标准 checkbox/dropdown/slider/input/color 仍各自回到既有池。
    if not isNew and group._exClearModuleCommonEntries then
        group:_exClearModuleCommonEntries()
    end
    BindCompositeGroup(group, db, onUpdate, opts)
    group._moduleCommonDb = db
    -- Grid 容器可能在同一帧被其他页面激活；页面需要能把实际显示的宿主
    -- 明确重绑回本次渲染的模块 DB，不能依赖对象池残留引用。
    group.RebindDB = function(self, nextDB)
        if type(nextDB) ~= "table" then return false end
        BindCompositeGroup(self, nextDB, self._exCompositeOnUpdate, self._exCompositeOpts)
        self._moduleCommonDb = nextDB
        return true
    end
    if not isNew then
        group:_exBuildModuleCommonEntries(flow)
        AttachCompositeRelease(group)
        if group._exApplyModuleCommonFlow then group:_exApplyModuleCommonFlow(flow) end
        return group
    end

    local palette = {
        text = { 0.96, 0.96, 0.97, 1 },
        value = { 0.204, 0.827, 0.599, 1 },
    }
    group:SetSize(groupWidth, groupHeight)
    -- ModuleCommon 只保留外层组边界和标题；这里是无装饰的内部定位宿主，
    -- 不再绘制第二层深色卡片，避免单个开关下方出现空白黑框。
    local header = CreateFrame("Frame", nil, group)
    header:SetSize(groupWidth, 40); header:SetPoint("TOPLEFT")
    local title = EXUI:CreateVisualFontString(header, EXFONTFRAME, "GameFontNormalHuge")
    title:SetPoint("LEFT", 15, 0); title:SetText(group._exCompositeLabel); title:SetTextColor(unpack(palette.text))
    group.labelText, group._exCompositeTitle = title, title
    local accent = EXUI:CreateVisualTexture(header, EXBASEFRAME)
    accent:SetPoint("LEFT", 6, 0); accent:SetSize(3, 21); accent:SetColorTexture(unpack(palette.value))

    local content = CreateFrame("Frame", nil, group)
    content:SetPoint("TOPLEFT", 0, -40)
    local settingsCard = CreateFrame("Frame", nil, content)

    local function EmitUpdate() CompositeEmitUpdate(group) end
    -- Root-bound ModuleCommon cards have no group prefix.  Their Checkbox /
    -- Dropdown / Input controls still need a real leaf path; forwarding the
    -- empty group path makes NotifyModuleValueChanged reject the change.
    local function NotifyModuleCommonField(path)
        local metadata = group._exCompositeOpts and group._exCompositeOpts._exWriteContext
        if metadata == nil then return false end
        if type(metadata) ~= "table" or type(metadata.moduleKey) ~= "string" or metadata.moduleKey == "" then
            error("CreateModuleCommonSettingsGroup requires Grid write context", 2)
        end
        local prefix = metadata.pathPrefix
        if prefix ~= nil and type(prefix) ~= "string" then
            error("CreateModuleCommonSettingsGroup Grid write context pathPrefix must be string or nil", 2)
        end
        local fullPath = type(prefix) == "string" and prefix ~= "" and (prefix .. "." .. path) or path
        EXUI:NotifyModuleValueChanged(metadata.moduleKey, fullPath, "committed")
        return true
    end
    local function SetValue(path, value, phase)
        CompositePathSet(group._exCompositeDb, path, value)
        -- 外部 DatabaseChanged 监听负责运行时同步；页面自己的预览则不应依赖那条
        -- 异步链。允许宿主在“字段已写入同一份 DB”的瞬间直接重套预览样式。
        if phase ~= "live" and type(group._exCompositeOpts.onFieldChanged) == "function" then
            group._exCompositeOpts.onFieldChanged(group._exCompositeDb, path, value)
        end
        if phase ~= "live" and not NotifyModuleCommonField(path) then EmitUpdate() end
    end

    -- ModuleCommonSettings 的连续 Slider 通过唯一 ModuleDB 通知流重套表面。
    local function CreateModuleCommonNotifyFlow(path)
        local metadata = group._exCompositeOpts and group._exCompositeOpts._exWriteContext
        if metadata == nil then return nil end
        if type(metadata) ~= "table" or type(metadata.moduleKey) ~= "string" or metadata.moduleKey == "" then
            error("CreateModuleCommonSettingsGroup requires Grid write context", 2)
        end
        if type(EXUI.CreateModuleNotifyFlow) ~= "function" then
            error("CreateModuleCommonSettingsGroup requires CreateModuleNotifyFlow", 2)
        end
        local prefix = metadata.pathPrefix
        if prefix ~= nil and type(prefix) ~= "string" then
            error("CreateModuleCommonSettingsGroup Grid write context pathPrefix must be string or nil", 2)
        end
        local fullPath = type(prefix) == "string" and prefix ~= "" and (prefix .. "." .. path) or path
        return EXUI:CreateModuleNotifyFlow({
            moduleKey = metadata.moduleKey,
            path = fullPath,
            readValue = function() return CompositePathValue(group._exCompositeDb, path) end,
            -- Core controller owns the only commit refresh.  live writes must
            -- not broadcast DatabaseChanged or rebuild this page.
            writeValue = function(value) SetValue(path, value, "live") end,
        })
    end

    group._exClearModuleCommonEntries = function(self)
        local factory = _G.ExwindFactory
        for _, mounted in ipairs(self._exModuleCommonEntries or {}) do
            local control = mounted.control
            if control and control._fromPool and factory then
                factory:Release(control._fromPool, control)
            elseif control then
                control:Hide()
                control:ClearAllPoints()
            end
            if mounted.card then
                mounted.card:Hide()
                mounted.card:ClearAllPoints()
            end
        end
        self._exModuleCommonEntries = {}
        self._exCompositeControls = {}
    end

    group._exBuildModuleCommonEntries = function(self, nextFlow)
        local activeFields = nextFlow.fields or {}
        local activeDb = self._exCompositeDb or {}
        self._exModuleCommonEntries = {}
        self._exModuleCommonCards = self._exModuleCommonCards or {}
        for index, field in ipairs(activeFields) do
            local path = tostring(field.path or field.key or "")
            if path ~= "" or field.type == "button" then
                local flowEntry = nextFlow.entries[index]
                local value = CompositePathValue(activeDb, path)
            local control, kind = nil, nil
            -- 保留每个控件的独立承载 Frame（下拉/对象池会依赖它的局部父级），
            -- 但取消背景与边框：视觉上只保留模块通用设置的外层卡片，不再出现小方格。
            local card = self._exModuleCommonCards[index]
            if not card then
                card = CreateFrame("Frame", nil, settingsCard, "BackdropTemplate")
                self._exModuleCommonCards[index] = card
                card:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
                card:SetBackdropColor(0, 0, 0, 0)
                card:SetBackdropBorderColor(0, 0, 0, 0)
            end
            card:SetParent(settingsCard)
            card:Show()
            card:SetSize(flowEntry.width, flowEntry.height)
            card:SetPoint("TOPLEFT", flowEntry.x, flowEntry.y)
            if field.type == "button" then
                control = EXUI:CreateButton(card, flowEntry.width - 20, 28, field.label or path, function()
                    local structureResult
                    if type(field.onClick) == "function" then
                        structureResult = field.onClick(self._exCompositeDb)
                    end
                    CompositeEmitUpdate(self)
                    if type(self._exCompositeOpts.onStructureChanged) == "function" then
                        self._exCompositeOpts.onStructureChanged(structureResult)
                    end
                end)
                control:SetPoint("TOPLEFT", 10, -16)
                kind = "button"
            elseif field.type == "checkbox" then
                control = EXUI:CreateCheckbox(card, field.label or path, value == true, function(v) self._exModuleCommonSetValue(path, v == true) end)
                control:SetPoint("TOPLEFT", 10, -11)
                kind = "check"
            elseif field.type == "dropdown" then
                control = EXUI:CreateDropdown(card, flowEntry.width - 20, field.label or path, field.items or {}, value, function(v) self._exModuleCommonSetValue(path, v) end)
                control:SetPoint("TOPLEFT", 10, -25)
                kind = "dropdown"
            elseif field.type == "lsm_background" or field.type == "lsm_border" or field.type == "lsm_texture" then
                local mediaType = field.type == "lsm_background" and "background"
                    or (field.type == "lsm_border" and "border" or "statusbar")
                control = EXUI:CreateLSMTextureDropdown(card, mediaType, flowEntry.width - 20, field.label or path, value, function(v)
                    self._exModuleCommonSetValue(path, v)
                end)
                control:SetPoint("TOPLEFT", 10, -25)
                kind = "dropdown"
            elseif field.type == "input" then
                control = EXUI:CreateEditBox(card, tostring(value or ""), flowEntry.width - 20, 28, field.label or path, {
                    labelPos = "top",
                    onEnter = function(v) SetValue(path, v or "") end,
                    onEditFocusLost = function(v) SetValue(path, v or "") end,
                })
                control:SetPoint("TOPLEFT", 10, -16)
                kind = "edit"
            elseif field.type == "color" then
                -- 颜色值仍按现有 R/G/B/A 字段保存；仅由通用封装组承载，
                -- 不让模块退回为四个散装滑动条。
                local colorDB, colorKey = self._exCompositeDb, path
                local colorParentPath, directColorKey = path:match("^(.*)%.([^%.]+)$")
                if colorParentPath and directColorKey then
                    local target = self._exCompositeDb
                    for part in string.gmatch(colorParentPath, "[^%.]+") do
                        target[part] = type(target[part]) == "table" and target[part] or {}
                        target = target[part]
                    end
                    colorDB, colorKey = target, directColorKey
                end
                control = EXUI:CreateColorButton(card, field.label or path, colorDB, colorKey, true, function()
                    if type(self._exCompositeOpts.onFieldChanged) == "function" then
                        self._exCompositeOpts.onFieldChanged(self._exCompositeDb, path)
                    end
                    if not NotifyModuleCommonField(path) then CompositeEmitUpdate(self) end
                end)
                control:SetPoint("TOPLEFT", 10, -14)
                kind = "color"
            else
                local lifecycle = CreateModuleCommonNotifyFlow(path)
                if lifecycle then
                    control = EXUI:CreateSlider(card, flowEntry.width - 20, field.label or path,
                        tonumber(field.min) or 0, tonumber(field.max) or 100, tonumber(value) or tonumber(field.min) or 0,
                        tonumber(field.step) or 1, nil, lifecycle)
                else
                    control = EXUI:CreateSlider(card, flowEntry.width - 20, field.label or path,
                        tonumber(field.min) or 0, tonumber(field.max) or 100, tonumber(value) or tonumber(field.min) or 0,
                        tonumber(field.step) or 1, nil, function(v) self._exModuleCommonSetValue(path, v) end)
                end
                control:SetPoint("TOPLEFT", 10, -25)
                kind = "slider"
            end
            if field.type ~= "button" then
                RegisterCompositeControl(self, control, path, kind)
            end
                self._exModuleCommonEntries[index] = { card = card, control = control, kind = kind, field = field }
            end
        end
    end
    group._exModuleCommonSetValue = SetValue
    group:_exBuildModuleCommonEntries(flow)

    group._exApplyModuleCommonFlow = function(self, nextFlow)
        self._exModuleCommonFlow = nextFlow
        -- 只有在线编辑器新增的空背景卡片允许其 layout.h 控制高度。其余
        -- ModuleCommon 仍由真实 fields Flow 固定高度，避免正式页面产生空白或裁切。
        if self._exCompositeOpts and self._exCompositeOpts.gridEditableHeight == true then
            self._exGridFixedHeight = nil
        else
            self._exGridFixedHeight = nextFlow.height
        end
        self:SetSize(nextFlow.width, nextFlow.height)
        local headerHeight = tonumber(nextFlow.headerHeight) or 40
        local cardInsetX = tonumber(nextFlow.cardInsetX)
        if cardInsetX == nil then cardInsetX = nextFlow.padding or 0 end
        local cardInsetY = tonumber(nextFlow.cardInsetY) or 8
        local cardBottomInset = tonumber(nextFlow.cardBottomInset) or cardInsetY
        header:SetSize(nextFlow.width, headerHeight)
        content:ClearAllPoints()
        content:SetPoint("TOPLEFT", 0, -headerHeight)
        content:SetSize(nextFlow.width, math.max(1, nextFlow.height - headerHeight))
        settingsCard:ClearAllPoints()
        settingsCard:SetPoint("TOPLEFT", content, "TOPLEFT", cardInsetX, -cardInsetY)
        local cardHeight = tonumber(nextFlow.cardHeight)
            or math.max(1, nextFlow.height - headerHeight - cardInsetY - cardBottomInset)
        settingsCard:SetSize(nextFlow.width - cardInsetX * 2, cardHeight)
        for index, entry in ipairs(nextFlow.entries) do
            local mounted = self._exModuleCommonEntries[index]
            if mounted then
                mounted.card:ClearAllPoints()
                mounted.card:SetPoint("TOPLEFT", settingsCard, "TOPLEFT",
                    entry.x - (nextFlow.entryOriginX or nextFlow.padding or 0), entry.y + nextFlow.contentTopInset)
                mounted.card:SetSize(entry.width, entry.height)
                local control = mounted.control
                if control then
                    if control.SetWidth then control:SetWidth(math.max(1, entry.width - 20)) end
                    control:ClearAllPoints()
                    if mounted.kind == "button" or mounted.kind == "edit" then
                        control:SetPoint("TOPLEFT", 10, -16)
                    elseif mounted.kind == "check" then
                        control:SetPoint("TOPLEFT", 10, -11)
                    elseif mounted.kind == "color" then
                        control:SetPoint("TOPLEFT", 10, -14)
                    else
                        control:SetPoint("TOPLEFT", 10, -25)
                    end
                end
            end
        end
    end
    group._exCompositeReflow = function(self, nextWidth)
        self:_exApplyModuleCommonFlow(EXUI:BuildModuleCommonSettingsFlow(nextWidth, self._exCompositeOpts))
    end
    group:_exApplyModuleCommonFlow(flow)

    group.RefreshFromDB = function(self)
        BindCompositeGroup(self, self._exCompositeDb, self._exCompositeOnUpdate, self._exCompositeOpts)
    end
    AttachCompositeRelease(group)
    return group
end

-- Aura Application Bar 是独立原生 Region：它只接收 maxApplications，
-- 不能借用普通计时条的 duration/fill/icon 设置，避免产生“能改但不会生效”的假控件。
-- Aura Duration Bar 同样是 AuraButton Adapter 绑定的原生 Region，而不是
-- TimerBarWidget。它故意不暴露图标、图标边框、填充模式等 TimerBar 专属字段：
-- 这些 Region 在原生 Aura Duration Bar 中不存在，暴露它们就是假 GUI。
function EXUI:CreateAuraDurationBarGroup(parent, width, label, db, key, onUpdate, opts)
    opts = type(opts) == "table" and opts or {}
    local fields = {
        { path = "enabled", type = "checkbox", label = L["启用计时条"] },
        { path = "texture", type = "input", label = L["条体材质"] },
        { path = "width", type = "slider", label = L["宽度"], min = 1, max = 800, step = 1 },
        { path = "height", type = "slider", label = L["高度"], min = 1, max = 120, step = 1 },
        { path = "x", type = "slider", label = L["X 偏移"], min = -1000, max = 1000, step = 1 },
        { path = "y", type = "slider", label = L["Y 偏移"], min = -1000, max = 1000, step = 1 },
        { path = "barColor", type = "color", label = L["前景颜色"] },
        { path = "barBgColor", type = "color", label = L["背景颜色"] },
        { path = "showBorder", type = "checkbox", label = L["显示边框"] },
        { path = "borderTexture", type = "input", label = L["边框材质"] },
        { path = "borderSize", type = "slider", label = L["边框粗细"], min = 0.1, max = 16, step = 0.1 },
        { path = "borderPadding", type = "slider", label = L["边框内距"], min = -32, max = 32, step = 1 },
        { path = "borderColor", type = "color", label = L["边框颜色"] },
    }
    if opts.forceEnabled and type(db) == "table" then
        local targetKey = key or "durationBar"
        db[targetKey] = type(db[targetKey]) == "table" and db[targetKey] or {}
        db[targetKey].enabled = true
        table.remove(fields, 1)
    end
    return self:CreateModuleCommonSettingsGroup(parent, width, label or L["计时条（原生 Aura Duration Bar）"], db, key or "durationBar", onUpdate, {
        columns = 3,
        poolType = opts.forceEnabled and "CompositeAuraDurationBarMainGroup" or "CompositeAuraDurationBarGroup",
        fields = fields,
    })
end

function EXUI:CreateAuraApplicationBarGroup(parent, width, label, db, key, onUpdate, opts)
    opts = type(opts) == "table" and opts or {}
    local fields = {
        { path = "enabled", type = "checkbox", label = L["启用层数条"] },
            { path = "maxApplications", type = "slider", label = L["最大层数"], min = 1, max = 99, step = 1 },
            { path = "texture", type = "input", label = L["条体材质"] },
            { path = "width", type = "slider", label = L["宽度"], min = 1, max = 800, step = 1 },
            { path = "height", type = "slider", label = L["高度"], min = 1, max = 120, step = 1 },
            { path = "x", type = "slider", label = L["X 偏移"], min = -1000, max = 1000, step = 1 },
            { path = "y", type = "slider", label = L["Y 偏移"], min = -1000, max = 1000, step = 1 },
            { path = "barColor", type = "color", label = L["前景颜色"] },
            { path = "barBgColor", type = "color", label = L["背景颜色"] },
    }
    if opts.forceEnabled and type(db) == "table" then
        local targetKey = key or "applicationBar"
        db[targetKey] = type(db[targetKey]) == "table" and db[targetKey] or {}
        db[targetKey].enabled = true
        table.remove(fields, 1)
    end
    return self:CreateModuleCommonSettingsGroup(parent, width, label or L["层数条（原生 Aura Application Bar）"], db, key or "applicationBar", onUpdate, {
        columns = 3,
        poolType = opts.forceEnabled and "CompositeAuraApplicationBarMainGroup" or "CompositeAuraApplicationBarGroup",
        fields = fields,
    })
end

-- =========================================================
-- 20.1 通用锚点设置组
-- 只管理 DB 字段与页面操作；实际 Frame 创建、拖动与依附仍由 AnchorController 负责。
-- =========================================================
function EXUI:CreateAnchorGroup(parent, width, label, db, key, onUpdate, opts)
    opts = type(opts) == "table" and opts or {}
    if key and type(db) == "table" then
        db[key] = type(db[key]) == "table" and db[key] or {}
        db = db[key]
    end
    db = type(db) == "table" and db or {}

    local xKey = opts.offsetXKey or "x"
    local yKey = opts.offsetYKey or "y"
    local attachKey = opts.attachEnabledKey or "attachToCustom"
    local targetKey = opts.attachTargetKey or "customAttachTarget"
    local supportsCustomAttach = opts.allowCustomAttach ~= false
    local defaultX = tonumber(opts.defaultOffsetX) or 0
    local defaultY = tonumber(opts.defaultOffsetY) or 0
    local groupWidth, groupHeight = width or 760, 92

    if db[xKey] == nil then db[xKey] = defaultX end
    if db[yKey] == nil then db[yKey] = defaultY end
    if supportsCustomAttach and db[attachKey] == nil then db[attachKey] = false end
    if supportsCustomAttach and db[targetKey] == nil then db[targetKey] = "" end

    local group, isNew = AcquireCompositeGroup("CompositeAnchorGroup", parent)
    group._exCompositeLabel = label or L["锚点设置"]
    BindCompositeGroup(group, db, onUpdate, opts)
    if not isNew then
        AttachCompositeRelease(group)
        ReflowCompositeGroup(group, groupWidth, groupHeight)
        if group._exAnchorRefresh then group:_exAnchorRefresh() end
        return group
    end

    local proxy = CreateCompositeProxy(group)
    db = proxy
    group:SetSize(groupWidth, groupHeight)
    group:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    group:SetBackdropColor(0.094, 0.094, 0.106, 1)
    group:SetBackdropBorderColor(1, 1, 1, 0.10)

    local accent = EXUI:CreateVisualTexture(group, EXBASEFRAME)
    accent:SetPoint("TOPLEFT", 7, -11)
    accent:SetSize(3, 20)
    accent:SetColorTexture(0.204, 0.827, 0.599, 1)

    local title = EXUI:CreateVisualFontString(group, EXFONTFRAME, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -8)
    title:SetText(group._exCompositeLabel)
    group._exCompositeTitle = title

    local function EmitUpdate() CompositeEmitUpdate(group) end
    -- 锚点是否启用只控制是否跟随目标；X/Y 仍是模块自身的控件配置，不能在此覆盖。
    -- 输入框与选择器常驻，方便先填路径再启用，不因勾选状态造成控件跳动。
    local attach, target, picker
    if supportsCustomAttach then
        attach = EXUI:CreateCheckbox(group, L["启用锚点"], db[attachKey] == true, function(value)
            db[attachKey] = value == true
            EmitUpdate()
        end)
        attach:SetPoint("TOPLEFT", 16, -55)
        RegisterCompositeControl(group, attach, attachKey, "check")

        local targetWidth = math.max(180, groupWidth - 330)
        target = EXUI:CreateEditBox(group, tostring(db[targetKey] or ""), targetWidth, 28, nil, {
            onEnter = function(value) db[targetKey] = value or ""; EmitUpdate() end,
            onEditFocusLost = function(value) db[targetKey] = value or ""; EmitUpdate() end,
        })
        target:SetPoint("TOPLEFT", 142, -50)
        RegisterCompositeControl(group, target, targetKey, "edit")

        picker = EXUI:CreateButton(group, 108, 28, L["锚点选择器"], function()
            if type(group._exCompositeOpts.onPickFrame) == "function" then
                group._exCompositeOpts.onPickFrame(group._exCompositeDb)
            end
        end)
        picker:SetPoint("TOPRIGHT", -16, -50)
        picker:SetShown(type(opts.onPickFrame) == "function")
    end

    group._anchorDb = proxy
    group._exCompositeReflow = function(self, nextWidth, nextHeight)
        if not supportsCustomAttach then return end
        local nextTargetWidth = math.max(180, nextWidth - 330)
        target:SetWidth(nextTargetWidth)
        target:ClearAllPoints(); target:SetPoint("TOPLEFT", self, "TOPLEFT", 142, -50)
        picker:ClearAllPoints(); picker:SetPoint("TOPRIGHT", self, "TOPRIGHT", -16, -50)
    end
    group:_exCompositeReflow(groupWidth, groupHeight)
    AttachCompositeRelease(group)
    return group
end

-- =========================================================
-- 21. 通用材质设置组
-- 用于普通 / Aura 显示的静态材质外观；宿主决定数据来源与生命周期。
-- =========================================================
function EXUI:CreateTextureGroup(parent, width, label, db, key, onUpdate, opts)
    opts = type(opts) == "table" and opts or {}
    if key and type(db) == "table" then
        db[key] = type(db[key]) == "table" and db[key] or {}
        db = db[key]
    end
    db = type(db) == "table" and db or {}
    local defaults = {
        fileID = "", width = 128, height = 128, x = 0, y = 0,
        alpha = 1, scale = 1, rotation = 0, flipH = false, flipV = false,
        colorR = 1, colorG = 1, colorB = 1, colorA = 1, blendMode = "BLEND",
    }
    for field, value in pairs(defaults) do
        if db[field] == nil then db[field] = value end
    end

    local groupWidth = width or 760
    local group, isNew = AcquireCompositeGroup("CompositeTextureGroup", parent)
    group._exCompositeLabel = label or L["材质"]
    BindCompositeGroup(group, db, onUpdate, opts)
    if not isNew then
        AttachCompositeRelease(group)
        ReflowCompositeGroup(group, groupWidth, 250)
        if group._exTextureConfigure then group:_exTextureConfigure() end
        return group
    end
    local proxy = CreateCompositeProxy(group)
    db = proxy
    group:SetSize(groupWidth, 250)
    group:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    group:SetBackdropColor(0.094, 0.094, 0.106, 1)
    group:SetBackdropBorderColor(1, 1, 1, 0.10)

    local accent = EXUI:CreateVisualTexture(group, EXBASEFRAME)
    accent:SetPoint("TOPLEFT", 7, -11)
    accent:SetSize(3, 20)
    accent:SetColorTexture(0.204, 0.827, 0.599, 1)
    local title = EXUI:CreateVisualFontString(group, EXFONTFRAME, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -8)
    title:SetText(group._exCompositeLabel)
    group._exCompositeTitle = title

    local function EmitUpdate() CompositeEmitUpdate(group) end
    local function AddSlider(field, titleText, minValue, maxValue, step, x, y, controlWidth)
        local slider = EXUI:CreateSlider(group, controlWidth or 170, titleText, minValue, maxValue, db[field], step, nil,
            function(value)
                db[field] = value
                EmitUpdate()
            end)
        slider:SetPoint("TOPLEFT", x, y)
        return RegisterCompositeControl(group, slider, field, "slider")
    end

    local fileInput = EXUI:CreateEditBox(group, tostring(db.fileID or ""), math.min(310, groupWidth - 48), 28,
        L["FileDataID / 路径"], {
            onEnter = function(value)
                db.fileID = tostring(value or "")
                EmitUpdate()
            end,
            onEditFocusLost = function(value)
                db.fileID = tostring(value or "")
                EmitUpdate()
            end,
            labelPos = "top",
        })
    fileInput:SetPoint("TOPLEFT", 16, -54)
    RegisterCompositeControl(group, fileInput, "fileID", "edit")

    -- 选择器是材质组件本身的可选能力。模块只能提供“如何挑选”的
    -- 回调，不能在自己的 Editor 里再创建/定位一枚私有按钮；这样池化
    -- 后也始终读取本次绑定的 DB 与回调。
    local texturePicker = EXUI:CreateButton(group, 108, 28, opts.pickerLabel or L["选择材质"], function()
        local activeOpts = group._exCompositeOpts or {}
        if type(activeOpts.onPickTexture) ~= "function" then return end
        activeOpts.onPickTexture(group._exCompositeDb and group._exCompositeDb.fileID, function(textureID)
            if type(group._exCompositeDb) ~= "table" then return end
            group._exCompositeDb.fileID = tostring(textureID or "")
            EXUI:RefreshCompositeGroupFromDB(group)
            CompositeEmitUpdate(group)
        end)
    end)
    texturePicker:SetPoint("TOPRIGHT", -16, -54)
    group._exTexturePickerButton = texturePicker
    group._exTextureConfigure = function(self)
        local activeOpts = self._exCompositeOpts or {}
        local picker = self._exTexturePickerButton
        if not picker then return end
        if picker.SetText then picker:SetText(activeOpts.pickerLabel or L["选择材质"]) end
        picker:SetShown(type(activeOpts.onPickTexture) == "function")
    end
    group:_exTextureConfigure()

    local widthSlider = AddSlider("width", L["宽度"], 1, 1024, 1, 16, -116)
    local heightSlider = AddSlider("height", L["高度"], 1, 1024, 1, 204, -116)
    local xSlider = AddSlider("x", L["X 偏移"], -1000, 1000, 1, 392, -116)
    local ySlider = AddSlider("y", L["Y 偏移"], -1000, 1000, 1, 580, -116)
    local alphaSlider = AddSlider("alpha", L["透明度"], 0, 1, 0.05, 16, -176)
    local scaleSlider = AddSlider("scale", L["缩放"], 0.05, 5, 0.05, 204, -176)
    local rotationSlider = AddSlider("rotation", L["旋转"], -180, 180, 1, 392, -176)

    local color = EXUI:CreateColorButton(group, L["材质颜色"], db, "color", true, EmitUpdate)
    color:SetPoint("TOPLEFT", 580, -164)
    RegisterCompositeControl(group, color, "", "color")
    local blend = EXUI:CreateDropdown(group, math.min(220, groupWidth - 48), L["混合模式"], {
        { "BLEND", "BLEND" }, { "ADD", "ADD" }, { "MOD", "MOD" },
        { "ALPHAKEY", "ALPHAKEY" }, { "DISABLE", "DISABLE" },
    }, db.blendMode, function(value)
        db.blendMode = value
        EmitUpdate()
    end)
    blend:SetPoint("TOPLEFT", 16, -226)
    RegisterCompositeControl(group, blend, "blendMode", "dropdown")

    local flipH = EXUI:CreateCheckbox(group, L["水平翻转"], db.flipH, function(value)
        db.flipH = value
        EmitUpdate()
    end)
    flipH:SetPoint("TOPLEFT", 254, -222)
    RegisterCompositeControl(group, flipH, "flipH", "check")
    local flipV = EXUI:CreateCheckbox(group, L["垂直翻转"], db.flipV, function(value)
        db.flipV = value
        EmitUpdate()
    end)
    flipV:SetPoint("TOPLEFT", 394, -222)
    RegisterCompositeControl(group, flipV, "flipV", "check")
    group._textureDb = proxy
    group._exCompositeReflow = function(self, nextWidth, nextHeight)
        local columnWidth = math.max(120, math.floor((nextWidth - 68) / 4))
        local col1 = 16
        local col2 = col1 + columnWidth + 18
        local col3 = col2 + columnWidth + 18
        local col4 = col3 + columnWidth + 18
        local fileWidth = math.min(310, math.max(160, nextWidth - 48))
        fileInput:SetWidth(fileWidth)
        texturePicker:ClearAllPoints(); texturePicker:SetPoint("TOPRIGHT", self, "TOPRIGHT", -16, -54)
        local top = { widthSlider, heightSlider, xSlider, ySlider }
        local topX = { col1, col2, col3, col4 }
        for index, slider in ipairs(top) do
            slider:SetWidth(columnWidth)
            slider:ClearAllPoints(); slider:SetPoint("TOPLEFT", self, "TOPLEFT", topX[index], -116)
        end
        for index, slider in ipairs({ alphaSlider, scaleSlider, rotationSlider }) do
            slider:SetWidth(columnWidth)
            slider:ClearAllPoints(); slider:SetPoint("TOPLEFT", self, "TOPLEFT", topX[index], -176)
        end
        color:ClearAllPoints(); color:SetPoint("TOPLEFT", self, "TOPLEFT", col4, -164)
        blend:SetWidth(math.min(220, math.max(120, nextWidth - 48)))
        flipH:ClearAllPoints(); flipH:SetPoint("TOPLEFT", self, "TOPLEFT", col2 + 50, -222)
        flipV:ClearAllPoints(); flipV:SetPoint("TOPLEFT", self, "TOPLEFT", col3 + 2, -222)
    end
    group:_exCompositeReflow(groupWidth, 250)
    AttachCompositeRelease(group)
    return group
end

-- =========================================================
-- 21.1 Aura 语义设置组
-- EXAura 只声明它要使用哪一种能力；控件树、对象池重绑与释放全部归 EXUI。
-- =========================================================
function EXUI:CreateAuraDispelBorderGroup(parent, width, label, db, key, onUpdate)
    return self:CreateModuleCommonSettingsGroup(parent, width, label or L["驱散边框"], db, key or "auraBorder", onUpdate, {
        columns = 3,
        poolType = "CompositeAuraDispelBorderGroup",
        fields = {
            { path = "enabled", type = "checkbox", label = L["启用驱散边框"] },
            { path = "showIcon", type = "checkbox", label = L["驱散边框带图标"] },
            { path = "style", type = "dropdown", label = L["驱散边框样式"], items = { { "Atlas", 0 }, { "Color", 1 } } },
        },
    })
end

function EXUI:CreateAuraSortGroup(parent, width, label, db, key, onUpdate)
    return self:CreateModuleCommonSettingsGroup(parent, width, label or L["Aura 内容排序"], db, key or "sort", onUpdate, {
        columns = 2,
        poolType = "CompositeAuraSortGroup",
        fields = {
            { path = "method", type = "dropdown", label = L["排序方式"], items = {
                { "默认", 0 }, { L["大减伤"], 1 }, { L["单位框减益"], 2 }, { L["仅重要"], 3 }, { L["到期"], 4 },
                { L["仅按到期"], 5 }, { L["名称"], 6 }, { L["仅按名称"], 7 }, { L["Aura 实例 ID"], 8 },
            } },
            { path = "direction", type = "dropdown", label = L["排序方向"], items = { { L["正常"], 0 }, { L["反向"], 1 } } },
        },
        onFieldChanged = function(target, path, value)
            if path == "method" or path == "direction" then target[path] = tonumber(value) or 0 end
        end,
    })
end

-- 这是 Aura 子元素的唯一结构性编辑器。它与 FontGroup/通用字段组一样
-- 由 Composite Host 管理，借用、重绑、释放不会把上一个规则的回调遗留在页面上。
function EXUI:CreateAuraChildElementsGroup(parent, width, label, db, key, onUpdate, opts)
    opts = type(opts) == "table" and opts or {}
    local target = db
    if key and type(target) == "table" then
        target[key] = type(target[key]) == "table" and target[key] or {}
        target = target[key]
    end
    target = type(target) == "table" and target or {}
    target.children = type(target.children) == "table" and target.children or {}

    local function NewChild(kind)
        if kind == "glow" then
            return { type = "glow", enabled = true, glowStyle = "Action Button Glow", glowColorR = 1, glowColorG = 1, glowColorB = 1, glowColorA = 1, glowOffset = 0, glowFrequency = 1, glowScale = 1 }
        end
        return { type = "text", enabled = true, text = L["文本"], font = "默认", size = 14, r = 1, g = 1, b = 1, a = 1, outline = "OUTLINE", shadow = false, x = 0, y = 0, justifyH = "CENTER", justifyV = "MIDDLE" }
    end
    local fields = {
        { type = "button", label = L["+ 文本"], onClick = function(activeTarget)
            activeTarget.children = type(activeTarget.children) == "table" and activeTarget.children or {}
            activeTarget.children[#activeTarget.children + 1] = NewChild("text")
            return #activeTarget.children
        end },
        { type = "button", label = L["+ 发光"], onClick = function(activeTarget)
            activeTarget.children = type(activeTarget.children) == "table" and activeTarget.children or {}
            activeTarget.children[#activeTarget.children + 1] = NewChild("glow")
            return #activeTarget.children
        end },
    }
    for index, child in ipairs(target.children) do
        local prefix = "children." .. tostring(index)
        fields[#fields + 1] = { path = prefix .. ".enabled", type = "checkbox", label = (child.type == "glow" and L["发光"] or L["文本"]) .. L[" 子元素 "] .. tostring(index) .. L[" · 启用"] }
        fields[#fields + 1] = { type = "button", label = L["删除 子元素 "] .. tostring(index), onClick = function(activeTarget)
            if type(activeTarget.children) == "table" then table.remove(activeTarget.children, index) end
        end }
        if child.type == "glow" then
            fields[#fields + 1] = { path = prefix .. ".glowStyle", type = "dropdown", label = L["发光 "] .. tostring(index) .. L[" · 样式"], items = { { L["动作条发光"], "Action Button Glow" }, { L["Proc 发光"], "Proc Alt Glow" } } }
            fields[#fields + 1] = { path = prefix .. ".glowColor", type = "color", label = L["发光 "] .. tostring(index) .. L[" · 颜色"] }
            fields[#fields + 1] = { path = prefix .. ".glowFrequency", type = "slider", label = L["发光 "] .. tostring(index) .. L[" · 频率"], min = 0.1, max = 5, step = 0.1 }
            fields[#fields + 1] = { path = prefix .. ".glowScale", type = "slider", label = L["发光 "] .. tostring(index) .. L[" · 大小"], min = 0.5, max = 3, step = 0.1 }
            fields[#fields + 1] = { path = prefix .. ".glowOffset", type = "slider", label = L["发光 "] .. tostring(index) .. L[" · 边距"], min = -50, max = 50, step = 1 }
        else
            -- 子元素必须仍是这一个 Composite Host 的字段，而不是 Editor 再在
            -- 外面拼一组 FontGroup。结构变化由 onStructureChanged 请求整页
            -- 重渲染；每一次渲染都只有一个可测量、可回收的根。
            fields[#fields + 1] = { path = prefix .. ".text", type = "input", label = L["文本 "] .. tostring(index) .. L[" · 示例"] }
            fields[#fields + 1] = { path = prefix .. ".font", type = "input", label = L["文本 "] .. tostring(index) .. L[" · 字体"] }
            fields[#fields + 1] = { path = prefix .. ".size", type = "slider", label = L["文本 "] .. tostring(index) .. L[" · 大小"], min = 6, max = 72, step = 1 }
            fields[#fields + 1] = { path = prefix .. ".color", type = "color", label = L["文本 "] .. tostring(index) .. L[" · 颜色"] }
            fields[#fields + 1] = { path = prefix .. ".x", type = "slider", label = L["文本 "] .. tostring(index) .. L[" · X 偏移"], min = -1000, max = 1000, step = 1 }
            fields[#fields + 1] = { path = prefix .. ".y", type = "slider", label = L["文本 "] .. tostring(index) .. L[" · Y 偏移"], min = -1000, max = 1000, step = 1 }
        end
    end
    -- 每一种子元素序列各有稳定的池键；同一种结构复用时只 Rebind，
    -- 增删元素后则借用匹配新字段数的宿主，绝不让旧字段树伪装成新结构。
    local signature = {}
    for _, child in ipairs(target.children) do signature[#signature + 1] = child.type == "glow" and "g" or "t" end
    local manager = self:CreateModuleCommonSettingsGroup(parent, width, label or L["子元素"], target, nil, onUpdate, {
        columns = 2,
        poolType = "CompositeAuraChildElementsGroup_" .. table.concat(signature, ""),
        fields = fields,
        onStructureChanged = opts.onStructureChanged,
    })
    return manager
end

-- 标准组合控件的无副作用 Grid 测量。数值与各 Create*Group 的实际 SetSize
-- 完全一致；将来修改控件高度时，必须同时改这里或改成共享常量，不能让 schema
-- 猜测内部控件树的高度。
local function FixedGridMeasure(height)
    return function()
        return { minHeight = height, preferredHeight = height }
    end
end

EXUI:RegisterGridComponentMeasure("fontgroup", FixedGridMeasure(220))
EXUI:RegisterGridComponentMeasure("icongroup", FixedGridMeasure(220))
EXUI:RegisterGridComponentMeasure("timerbargroup", FixedGridMeasure(282))
EXUI:RegisterGridComponentMeasure("texturegroup", FixedGridMeasure(250))
EXUI:RegisterGridComponentMeasure("anchorgroup", FixedGridMeasure(92))
EXUI:RegisterGridComponentMeasure("soundgroup", function(width, opts)
    local height = EXUI:BuildSoundGroupLayout(width, opts).height
    return { minHeight = height, preferredHeight = height }
end)
EXUI:RegisterGridComponentMeasure("widgetlayout", function(_, opts)
    opts = type(opts) == "table" and opts or {}
    local tall = opts.includeMaxPerRow ~= false or opts.includeWrapDirection == true
    -- Must exactly match CreateWidgetLayoutGroup's real 134/88 card height.
    -- The stale 118/72 measurement let the following Grid card overlap the
    -- bottom controls, so direction/spacing/maxVisible could appear clickable
    -- while their mouse input was intercepted by another component.
    local height = tall and 134 or 88
    return { minHeight = height, preferredHeight = height }
end)
EXUI:RegisterGridComponentMeasure("modulecommonsettings", function(width, opts)
    local flow = EXUI:BuildModuleCommonSettingsFlow(width, opts)
    return { minHeight = flow.height, preferredHeight = flow.height }
end)
-- Aura 专用语义组同样是标准 Composite Host；高度只从同一 Flow 合同推导。
-- 页面 schema 不得复制字段数或手写像素高度。
local function AuraMeasureFields(count)
    local fields = {}
    for index = 1, count do fields[index] = { path = "field" .. tostring(index), type = "slider" } end
    return fields
end
local function AuraFlowMeasure(countResolver)
    return function(width, _, db, item)
        return EXUI:BuildModuleCommonSettingsFlow(width, { fields = AuraMeasureFields(countResolver(db, item)), maxColumns = 4 })
    end
end
EXUI:RegisterGridComponentMeasure("auradurationbargroup", AuraFlowMeasure(function() return 13 end))
EXUI:RegisterGridComponentMeasure("auraapplicationbargroup", AuraFlowMeasure(function() return 9 end))
EXUI:RegisterGridComponentMeasure("auradispelbordergroup", AuraFlowMeasure(function() return 3 end))
EXUI:RegisterGridComponentMeasure("aurasortgroup", AuraFlowMeasure(function() return 2 end))
EXUI:RegisterGridComponentMeasure("aurachildelementsgroup", AuraFlowMeasure(function(db, item)
    local source = type(db) == "table" and db or {}
    local target = item and item.key and type(source[item.key]) == "table" and source[item.key] or source
    local count = 2 -- add text / add glow
    for _, child in ipairs(type(target.children) == "table" and target.children or {}) do
        count = count + 2 + (child.type == "glow" and 5 or 6)
    end
    return count
end))

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
local STANDARD_PREVIEW_DOCK_BACKGROUND = { 148 / 255, 165 / 255, 252 / 255, 1 } -- #94A5FC

-- C_Timer.After callbacks do not retain the synchronous call stack that led to
-- Page:Render.  A failure used to look like a silent empty PreviewDock because
-- it could stop between Grid Render and preview.render.  Keep the four public
-- lifecycle stages explicit so the game error has a stable, searchable contract
-- instead of an anonymous delayed-callback stack.
local STANDARD_MODULE_PAGE_STAGES = {
    grid = "grid",
    slider = "slider",
    audit = "audit",
    preview = "preview",
}

local function BuildStandardModulePageStageError(moduleKey, stage, original)
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

local function RequireStandardModulePageFunction(value, name)
    if type(value) ~= "function" then
        error("CreateStandardModulePage requires " .. name .. " function", 3)
    end
    return value
end

local function ApplyStandardModulePreviewDockStyle(dock)
    if not dock or type(dock.SetBackdrop) ~= "function" or type(dock.SetBackdropColor) ~= "function" then
        error("StandardModulePage requires BackdropTemplate PreviewDock", 3)
    end
    dock:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    dock:SetBackdropBorderColor(0.20, 0.62, 0.90, 0.45)
    dock:SetBackdropColor(unpack(STANDARD_PREVIEW_DOCK_BACKGROUND))
end

local function ResolveStandardModulePageLayout(layout, context)
    local resolved = type(layout) == "function" and layout(context) or layout
    if type(resolved) ~= "table" then
        error("StandardModulePage layout must resolve to a table", 3)
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
    RequireStandardModulePageFunction(binding.getConfig, "binding.getConfig")

    local preview = options.preview
    if type(preview) ~= "table" then error("CreateStandardModulePage requires preview surface", 2) end
    local previewRender = RequireStandardModulePageFunction(preview.render or preview.Render, "preview.render")
    local previewRelease = RequireStandardModulePageFunction(preview.release or preview.Release, "preview.release")

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
        dockHeight = math.max(1, tonumber(preview.height) or 160),
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
        }
    end

    function controller:SetDockHeight(height)
        height = tonumber(height)
        if not height or height <= 0 then error("StandardModulePage dock height must be positive", 2) end
        self.dockHeight = height
        if self.previewDock then self.previewDock:SetHeight(height) end
    end

    function controller:RefreshGridControls()
        local grid = _G.ExwindGrid
        if grid and self.scrollChild and type(grid.RefreshContainerControlsFromDB) == "function" then
            return grid:RefreshContainerControlsFromDB(self.scrollChild)
        end
        return false
    end

    function controller:ClearActiveOwnership()
        if EXUI.ActivePageFrame == self.scrollChild then
            EXUI.ActivePageFrame = nil
            EXUI.CurrentModule = nil
            if EXUI.ModuleScrollFrame == self.scrollFrame then
                EXUI.ModuleScrollFrame = nil
            end
        end
    end

    function controller:ReleasePreview()
        if not self.previewMounted then return end
        self.previewMounted = false
        self.previewRelease(self.previewDock, BuildContext(self))
    end

    function controller:ReleaseGrid()
        local grid = _G.ExwindGrid
        if grid and self.scrollChild and type(grid.ReleaseContainerWidgets) == "function" then
            grid:ReleaseContainerWidgets(self.scrollChild)
        end
        self.gridRendered = false
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
        local grid = _G.ExwindGrid
        self.gridRendered = false
        pcall(function()
            if grid and self.scrollChild and type(grid.ReleaseContainerWidgets) == "function" then
                grid:ReleaseContainerWidgets(self.scrollChild)
            end
        end)
        pcall(function() self:ClearActiveOwnership() end)
        pcall(function()
            if self.previewDock then self.previewDock:Hide() end
        end)
    end

    function controller:RaiseStageFailure(generation, stage, original, isDiagnostic)
        local diagnostic = isDiagnostic and original
            or BuildStandardModulePageStageError(self.moduleKey, stage, original)
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
            return BuildStandardModulePageStageError(self.moduleKey, stage, original)
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
        if self.previewDock then self.previewDock:Hide() end
    end

    function controller:EnsureFrames(contentFrame)
        if not contentFrame or type(contentFrame.SetPoint) ~= "function" then
            error("StandardModulePage Render requires contentFrame", 2)
        end
        self.contentFrame = contentFrame
        if self.scrollFrame then return end

        local scrollFrame = CreateFrame("ScrollFrame", nil, contentFrame, "ScrollFrameTemplate")
        scrollFrame:EnableMouseWheel(true)
        if self.applyScrollSkin then self.applyScrollSkin(scrollFrame) end
        local scrollChild = CreateFrame("Frame", nil, scrollFrame)
        scrollChild:SetHeight(1)
        scrollFrame:SetScrollChild(scrollChild)

        local dock = CreateFrame("Frame", nil, contentFrame, "BackdropTemplate")
        ApplyStandardModulePreviewDockStyle(dock)
        dock:SetHeight(self.dockHeight)

        self.scrollFrame = scrollFrame
        self.scrollChild = scrollChild
        self.previewDock = dock
        -- 页面只保存标准宿主引用，不能保留 module private preview/session。
        self.page._scrollFrame = scrollFrame
        self.page._scrollChild = scrollChild
        self.page._previewDock = dock

        scrollFrame:HookScript("OnHide", function()
            self:Teardown()
        end)
        scrollFrame:HookScript("OnShow", function()
            if self._suppressOnShow or self.gridRendered or not self.contentFrame then return end
            self:Render(self.contentFrame)
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
        dock:SetParent(contentFrame)
        dock:ClearAllPoints()
        dock:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 4, -4)
        dock:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", -24, -4)
        dock:SetHeight(self.dockHeight)
    end

    function controller:Render(contentFrame)
        self:EnsureFrames(contentFrame)
        -- 同一页被路由重复 Render 时不会触发 OnHide；必须先交还上一轮
        -- Grid/preview，才能重新绑定本轮唯一 container/session。
        if self.gridRendered or self.previewMounted then
            self:ReleasePreview()
            self:ReleaseGrid()
        end
        self.renderGeneration = self.renderGeneration + 1
        local generation = self.renderGeneration
        local scrollFrame, scrollChild, dock = self.scrollFrame, self.scrollChild, self.previewDock

        -- 每次 page show/render 都强制统一 PreviewDock 色，不能继承池化宿主旧背景。
        self:PlacePreviewDock(contentFrame)
        ApplyStandardModulePreviewDockStyle(dock)
        dock:Show()

        scrollFrame:SetParent(contentFrame)
        scrollFrame:ClearAllPoints()
        if self.dockPolicy == "external-left" then
            scrollFrame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 4, -4)
        else
            scrollFrame:SetPoint("TOPLEFT", dock, "BOTTOMLEFT", 0, -6)
        end
        scrollFrame:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -24, 4)
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

            self:RunDelayedStage(generation, STANDARD_MODULE_PAGE_STAGES.grid, function()
                if not grid then error("StandardModulePage requires ExwindGrid", 2) end
                config = self.binding.getConfig()
                if type(config) ~= "table" then error("StandardModulePage binding getConfig returned non-table", 2) end
                local width = contentFrame:GetWidth()
                if width < 100 then width = 820 end
                scrollChild:SetWidth(width - 16)
                scrollChild:SetParent(scrollFrame)
                scrollChild:ClearAllPoints()
                scrollChild:SetPoint("TOPLEFT", 0, 0)
                scrollChild:Show()

                EXUI.ActivePageFrame = scrollChild
                EXUI.CurrentModule = self.moduleKey
                -- FocusCurrentModuleGridKey 的公开实现只从 EXUI 读取当前页面的
                -- ScrollFrame。标准外壳在这里唯一注册，模块页不得再各自传私有 host。
                EXUI.ModuleScrollFrame = scrollFrame
                context = BuildContext(self)
                context.config = config
                columns = type(self.getColumns) == "function" and self.getColumns(context) or self.getColumns
                columns = tonumber(columns)
                if not columns or columns <= 0 then error("StandardModulePage resolved invalid Grid column count", 2) end
                if type(grid.SetContainerCols) == "function" then grid:SetContainerCols(scrollChild, columns) end
                grid:Render(scrollChild, ResolveStandardModulePageLayout(self.layout, context), config, self.moduleKey)
                self.gridRendered = true
                context = BuildContext(self)
                context.config = config
                context.columns = columns
            end)

            self.binding.contract.page = true

            -- Surface 是允许懒创建的正式声明：首次 preview mount 才会把同一个
            -- surface 写入 binding.contract.surface。故必须先 mount 当前模块，
            -- 再审计当前模块；不能为通过 audit 在模块加载期虚构 session。
            self:RunDelayedStage(generation, STANDARD_MODULE_PAGE_STAGES.preview, function()
                if self.afterGridLayout then self.afterGridLayout(context) end
                self.previewRender(dock, context)
                self.previewMounted = true
            end)

            self:RunDelayedStage(generation, STANDARD_MODULE_PAGE_STAGES.audit, function()
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
