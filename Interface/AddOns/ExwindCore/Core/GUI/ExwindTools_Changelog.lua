-- =============================================================
-- ExwindTools_Changelog.lua
-- 统一更新日志查看器：只拥有窗口与 TAB，不拥有任何插件的日志正文或已读状态。
-- EXBoss / ExwindTools 分别在自己的加载链注册日志源。
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end

local L = ExwindTools.L
    or (_G.ExwindLocale and _G.ExwindLocale.GetProxy and _G.ExwindLocale.GetProxy())
    or setmetatable({}, { __index = function(_, key) return key end })

local Viewer = ExwindTools.ChangelogViewer or {}
ExwindTools.ChangelogViewer = Viewer
Viewer.Sources = Viewer.Sources or {}
Viewer.Order = { "boss", "tools" }

local viewerFrame

local PANEL_THEME = {
    Background = { 0, 0, 0, 1 },
    Border = { 0.22, 0.56, 0.34, 0.9 },
    BodyText = { 0.84, 0.86, 0.89, 1.0 },
    BulletText = { 0.90, 0.92, 0.95, 1.0 },
    NoteText = { 0.95, 0.74, 0.45, 1.0 },
    H1Text = { 1.00, 0.86, 0.45, 1.0 },
    H2Text = { 0.43, 0.68, 0.86, 1.0 },
    DividerText = { 0.52, 0.64, 0.74, 0.75 },
}

local PANEL_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 14,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local FONT_PATH = (GameFontNormal and select(1, GameFontNormal:GetFont())) or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

local function Trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$") or ""
end

local function IsChineseLocale()
    local locale = (GetLocale and GetLocale()) or "zhCN"
    return locale == "zhCN" or locale == "zhTW"
end

local function GetSource(sourceID)
    return Viewer.Sources[sourceID]
end

local function GetSourceContent(source)
    if not source or type(source.GetContent) ~= "function" then
        return ""
    end
    return tostring(source:GetContent() or "")
end

local function SourceHasContent(source)
    return Trim(GetSourceContent(source)) ~= ""
end

local function GetSourceTitle(source)
    if source and type(source.GetTitle) == "function" then
        local title = source:GetTitle()
        if type(title) == "string" and title ~= "" then
            return title
        end
    end
    return (source and source.title) or L["更新日志"]
end

function Viewer:RegisterSource(sourceID, source)
    if type(sourceID) ~= "string" or sourceID == "" then
        error("changelog source id must be a non-empty string", 2)
    end
    if type(source) ~= "table" or type(source.GetVersion) ~= "function" or type(source.GetContent) ~= "function" then
        error("changelog source must provide GetVersion and GetContent", 2)
    end
    source.id = sourceID
    self.Sources[sourceID] = source
end

function Viewer:GetDefaultSourceID()
    if self.ActiveSourceID and GetSource(self.ActiveSourceID) then
        return self.ActiveSourceID
    end
    for _, sourceID in ipairs(self.Order) do
        if GetSource(sourceID) then
            return sourceID
        end
    end
    for sourceID in pairs(self.Sources) do
        return sourceID
    end
    return nil
end

local function ResolveLineStyle(line, baseSize)
    local h2 = line:match("^%s*@H2@%s*(.+)$") or line:match("^%s*##%s+(.+)$")
    if h2 then
        return h2, baseSize + 3, PANEL_THEME.H2Text, "", 7, "h2"
    end

    local h1 = line:match("^%s*@H1@%s*(.+)$") or line:match("^%s*#%s+(.+)$")
    if h1 then
        h1 = h1:gsub("%s+%d%d%d%d%-%d%d%-%d%d%s+%d%d:%d%d$", "")
        return h1, baseSize + 11, PANEL_THEME.H1Text, "OUTLINE", 10, "h1"
    end

    if line:match("^%s*$") then
        return "", baseSize, PANEL_THEME.BodyText, "", math.max(6, math.floor(baseSize * 0.5)), "blank"
    end
    if line:match("^%s*备注:") then
        return line, baseSize, PANEL_THEME.NoteText, "", math.max(6, math.floor(baseSize * 0.48)), "note"
    end
    if line:match("^%s*%-") then
        return line, baseSize, PANEL_THEME.BulletText, "", math.max(4, math.floor(baseSize * 0.42)), "bullet"
    end
    return line, baseSize, PANEL_THEME.BodyText, "", math.max(4, math.floor(baseSize * 0.4)), "body"
end

local function AcquireLine(frame, index)
    frame.LinePool = frame.LinePool or {}
    local line = frame.LinePool[index]
    if line then return line end
    line = frame.ScrollChild:CreateFontString(nil, "OVERLAY")
    line:SetJustifyH("LEFT")
    line:SetJustifyV("TOP")
    if line.SetNonSpaceWrap then line:SetNonSpaceWrap(true) end
    frame.LinePool[index] = line
    return line
end

local function AcquireDivider(frame, index)
    frame.DividerPool = frame.DividerPool or {}
    local divider = frame.DividerPool[index]
    if divider then return divider end
    divider = frame.ScrollChild:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(unpack(PANEL_THEME.DividerText))
    frame.DividerPool[index] = divider
    return divider
end

local function NormalizeLocaleLine(line, source, blockLanguage)
    local isChinese = IsChineseLocale()
    if type(source.IsChineseLocale) == "function" then
        isChinese = source:IsChineseLocale() == true
    end

    -- 发布器历史上同时产出过逐行 @CN@/@EN@ 与区块 [CN_0]...[CN_1]
    -- 两种格式。语言状态收敛在共享查看器，避免每个插件各自解析。
    local marker = Trim(line)
    if marker == "[CN_0]" then return nil, "CN" end
    if marker == "[CN_1]" then return nil, nil end
    if marker == "[EN_0]" then return nil, "EN" end
    if marker == "[EN_1]" then return nil, nil end
    if blockLanguage == "CN" and not isChinese then return nil, blockLanguage end
    if blockLanguage == "EN" and isChinese then return nil, blockLanguage end

    if line:match("^@CN@") then
        if not isChinese then return nil, blockLanguage end
        return (line:gsub("^@CN@%s?", "")), blockLanguage
    end
    if line:match("^@EN@") then
        if isChinese then return nil, blockLanguage end
        return (line:gsub("^@EN@%s?", "")), blockLanguage
    end
    return line, blockLanguage
end

local function RenderContent(frame, source)
    local content = GetSourceContent(source)
    if Trim(content) == "" then content = L["暂无更新日志内容。"] end

    local baseSize = 14
    if type(source.GetFontSize) == "function" then
        local requested = tonumber(source:GetFontSize())
        if requested then baseSize = math.max(10, math.min(28, math.floor(requested))) end
    end

    local contentWidth = math.max(320, frame:GetWidth() - 62)
    local y, lineIndex, dividerIndex = 0, 0, 0
    local seenH1 = false
    local blockLanguage = nil
    for rawLine in (content .. "\n"):gmatch("(.-)\n") do
        local line
        line, blockLanguage = NormalizeLocaleLine(rawLine, source, blockLanguage)
        if line then
            if type(source.TransformLine) == "function" then
                line = tostring(source.TransformLine(line) or "")
            end
            lineIndex = lineIndex + 1
            local fs = AcquireLine(frame, lineIndex)
            local lineText, fontSize, color, flags, bottomGap, styleType = ResolveLineStyle(line, baseSize)
            if styleType == "h1" then
                if seenH1 then y = y + math.max(18, math.floor(baseSize * 1.4)) end
                seenH1 = true
            end
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", 0, -y)
            fs:SetWidth(contentWidth)
            fs:SetFont(FONT_PATH, fontSize, flags)
            fs:SetTextColor(color[1], color[2], color[3], color[4])
            if lineText == "" then
                fs:SetText(" ")
                y = y + bottomGap
            else
                fs:SetText(lineText)
                y = y + fs:GetStringHeight() + bottomGap
                if styleType == "h1" then
                    dividerIndex = dividerIndex + 1
                    local divider = AcquireDivider(frame, dividerIndex)
                    divider:ClearAllPoints()
                    divider:SetPoint("TOPLEFT", 0, -y)
                    divider:SetSize(contentWidth, 1)
                    divider:Show()
                    y = y + 12
                end
            end
            fs:Show()
        end
    end
    for index = lineIndex + 1, #frame.LinePool do frame.LinePool[index]:Hide() end
    for index = dividerIndex + 1, #frame.DividerPool do frame.DividerPool[index]:Hide() end
    frame.ScrollChild:SetSize(contentWidth, math.max(1, y + 10))
    frame.ScrollFrame:SetVerticalScroll(0)
end

local function EnsureViewerFrame()
    if viewerFrame then return viewerFrame end
    viewerFrame = CreateFrame("Frame", "ExwindChangelogFrame", UIParent, "BackdropTemplate")
    viewerFrame:SetSize(860, 620)
    viewerFrame:SetBackdrop(PANEL_BACKDROP)
    viewerFrame:SetBackdropColor(unpack(PANEL_THEME.Background))
    viewerFrame:SetBackdropBorderColor(unpack(PANEL_THEME.Border))
    viewerFrame:SetPoint("CENTER")
    viewerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    viewerFrame:SetFrameLevel(200)
    viewerFrame:SetToplevel(true)
    viewerFrame:SetMovable(true)
    viewerFrame:EnableMouse(true)
    viewerFrame:EnableKeyboard(true)
    viewerFrame:RegisterForDrag("LeftButton")
    viewerFrame:SetClampedToScreen(false)
    if viewerFrame.SetPropagateKeyboardInput then viewerFrame:SetPropagateKeyboardInput(true) end
    viewerFrame:SetScript("OnDragStart", viewerFrame.StartMoving)
    viewerFrame:SetScript("OnDragStop", viewerFrame.StopMovingOrSizing)
    viewerFrame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
            self:Hide()
            return
        end
        if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
    end)
    viewerFrame:SetScript("OnHide", function() GameTooltip:Hide() end)

    local title = viewerFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOPLEFT", 20, -15)
    viewerFrame.Title = title
    local close = CreateFrame("Button", nil, viewerFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -3, -3)
    close:SetScript("OnClick", function() viewerFrame:Hide() end)

    local tabHost = CreateFrame("Frame", nil, viewerFrame)
    tabHost:SetPoint("TOPLEFT", 18, -42)
    tabHost:SetPoint("TOPRIGHT", -34, -42)
    tabHost:SetHeight(30)
    viewerFrame.TabHost = tabHost
    viewerFrame.TabButtons = {}

    local scrollFrame = CreateFrame("ScrollFrame", nil, viewerFrame, "ScrollFrameTemplate")
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetPoint("TOPLEFT", 18, -82)
    scrollFrame:SetPoint("BOTTOMRIGHT", -34, 18)
    viewerFrame.ScrollFrame = scrollFrame
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(1, 1)
    scrollFrame:SetScrollChild(scrollChild)
    viewerFrame.ScrollChild = scrollChild
    viewerFrame.LinePool = {}
    viewerFrame.DividerPool = {}
    if _G.UISpecialFrames then
        local found = false
        for _, name in ipairs(_G.UISpecialFrames) do
            if name == "ExwindChangelogFrame" then found = true break end
        end
        if not found then table.insert(_G.UISpecialFrames, "ExwindChangelogFrame") end
    end
    viewerFrame:Hide()
    return viewerFrame
end

local TAB_STYLE = {
    activeBackground = { 0.075, 0.125, 0.165, 0.96 },
    hoverBackground = { 0.075, 0.115, 0.150, 0.90 },
    idleBackground = { 0.025, 0.035, 0.050, 0.56 },
    activeText = { 0.90, 0.95, 1.00, 1.00 },
    idleText = { 0.52, 0.60, 0.69, 1.00 },
    hoverText = { 0.76, 0.86, 0.94, 1.00 },
    accent = { 0.28, 0.80, 0.91, 1.00 },
}

local function SetTabVisual(button, active, hovered)
    button._tabActive = active == true
    if active then
        button.Background:SetColorTexture(unpack(TAB_STYLE.activeBackground))
        button.Label:SetTextColor(unpack(TAB_STYLE.activeText))
        button.Accent:Show()
    elseif hovered then
        button.Background:SetColorTexture(unpack(TAB_STYLE.hoverBackground))
        button.Label:SetTextColor(unpack(TAB_STYLE.hoverText))
        button.Accent:Hide()
    else
        button.Background:SetColorTexture(unpack(TAB_STYLE.idleBackground))
        button.Label:SetTextColor(unpack(TAB_STYLE.idleText))
        button.Accent:Hide()
    end
end

local function CreateTabButton(parent)
    local button = CreateFrame("Button", nil, parent)
    button:SetHeight(30)
    button.Background = button:CreateTexture(nil, "BACKGROUND")
    button.Background:SetAllPoints()
    button.Label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    button.Label:SetPoint("CENTER", 0, 1)
    button.Accent = button:CreateTexture(nil, "ARTWORK")
    button.Accent:SetPoint("BOTTOMLEFT", 0, 0)
    button.Accent:SetPoint("BOTTOMRIGHT", 0, 0)
    button.Accent:SetHeight(3)
    button.Accent:SetColorTexture(unpack(TAB_STYLE.accent))
    button:SetScript("OnEnter", function(self)
        if not self._tabActive then SetTabVisual(self, false, true) end
    end)
    button:SetScript("OnLeave", function(self)
        if not self._tabActive then SetTabVisual(self, false, false) end
    end)
    return button
end

local function RebuildTabs(frame, activeSourceID)
    local previous, tabIndex = nil, 0
    for _, sourceID in ipairs(Viewer.Order) do
        local source = GetSource(sourceID)
        if source then
            tabIndex = tabIndex + 1
            local button = frame.TabButtons[tabIndex]
            if not button then
                button = CreateTabButton(frame.TabHost)
                frame.TabButtons[tabIndex] = button
            end
            button:ClearAllPoints()
            button.Label:SetText(GetSourceTitle(source))
            button:SetWidth(math.max(132, button.Label:GetStringWidth() + 40))
            if previous then button:SetPoint("LEFT", previous, "RIGHT", 4, 0) else button:SetPoint("LEFT", 0, 0) end
            button.sourceID = sourceID
            button:SetScript("OnClick", function(self)
                Viewer:Show(self.sourceID, { markSeen = true, markShown = true })
            end)
            SetTabVisual(button, sourceID == activeSourceID, false)
            button:Show()
            previous = button
        end
    end
    for index = tabIndex + 1, #frame.TabButtons do frame.TabButtons[index]:Hide() end
end

function Viewer:Show(sourceID, options)
    options = options or {}
    sourceID = sourceID or self:GetDefaultSourceID()
    local source = GetSource(sourceID)
    if not source then return false end
    if options.markSeen and type(source.MarkSeen) == "function" then source:MarkSeen() end
    if options.markShown and type(source.MarkPopupShown) == "function" then source:MarkPopupShown() end

    self.ActiveSourceID = sourceID
    local frame = EnsureViewerFrame()
    frame.Title:SetText(GetSourceTitle(source))
    RebuildTabs(frame, sourceID)
    RenderContent(frame, source)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(200)
    frame:Show()
    frame:Raise()
    return true
end

function Viewer:ShowManual()
    return self:Show(nil, { markSeen = true, markShown = true })
end

function Viewer:HasContent(sourceID)
    return SourceHasContent(GetSource(sourceID))
end
