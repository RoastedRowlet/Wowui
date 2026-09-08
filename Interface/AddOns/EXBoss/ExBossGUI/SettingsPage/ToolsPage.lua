---@diagnostic disable: undefined-global, undefined-field

ExBoss.UI.Panel.ToolsPage = ExBoss.UI.Panel.ToolsPage or {}
local Page = ExBoss.UI.Panel.ToolsPage
local L = ExBoss.L or setmetatable({}, { __index = function(_, key) return key end })
local EXUI = _G.ExwindTools and _G.ExwindTools.UI

local selectedKey = "mythiccast"
local leftRoot
local leftHostFrame
local listScroll
local listChild
local contentHostFrame
local activeButtons = {}
local buttonPool = {}
local resetButton = nil
local searchBox = nil
local searchText = ""
local sidebarDivider = nil

-- 确认弹窗（只注册一次）
if not StaticPopupDialogs["EXBOSS_RESET_TOOL_CONFIRM"] then
    StaticPopupDialogs["EXBOSS_RESET_TOOL_CONFIRM"] = {
        text = L["确定要重置「%s」的所有配置吗？\n\n此操作不可撤销。"],
        button1 = L["确定重置"],
        button2 = CANCEL,
        OnAccept = function(_, data)
            local resetFn = ExBoss.ResetModuleConfig and ExBoss.ResetModuleConfig[data]
            if resetFn then
                resetFn()
                if leftHostFrame and contentHostFrame then
                    Page:Render(leftHostFrame, contentHostFrame)
                end
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
end

local ITEMS = {
    { key = "mythiccast",       titleKey = "大米怪物施法", moduleKey = "ExBoss.Tools.MythicCast" },
    { key = "interrupttracker", titleKey = "队友打断监控", moduleKey = "ExBoss.Tools.InterruptTracker" },
}

local ITEMS_BY_KEY = {}
for _, item in ipairs(ITEMS) do
    ITEMS_BY_KEY[item.key] = item
end

local function GetTitle(item)
    return L[item.titleKey or ""]
end

function Page:GetExportModuleKeys()
    local out = {}
    local seen = {}
    for _, item in ipairs(ITEMS) do
        local key = item.moduleKey
        if type(key) == "string" and key ~= "" and not seen[key] then
            seen[key] = true
            out[#out + 1] = key
        end
    end
    return out
end

local function HideEmbeddedPages()
    local pages = {
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.MythicCastPage,
        ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.InterruptTrackerPage,
    }
    for _, page in ipairs(pages) do
        if page and page.Hide then
            page:Hide()
        end
    end
end

local function ClearButtons()
    for _, button in ipairs(activeButtons) do
        button:Hide()
        button:ClearAllPoints()
        button:SetScript("OnClick", nil)
        buttonPool[#buttonPool + 1] = button
    end
    wipe(activeButtons)
end

local function AcquireListButton()
    local button = table.remove(buttonPool)
    if button then
        button:SetParent(listChild)
        return button
    end

    if ExBoss.UI and ExBoss.UI.CreateSidebarModuleButton then
        button = ExBoss.UI.CreateSidebarModuleButton(listChild)
    else
        button = CreateFrame("Button", nil, listChild, "BackdropTemplate")
        button:SetHeight(28)
        button.fs = EXUI:CreateVisualFontString(button, EXFONTFRAME, "GameFontHighlightSmall")
        button.fs:SetPoint("LEFT", 12, 0)
        button.fs:SetPoint("RIGHT", -8, 0)
        button.fs:SetJustifyH("LEFT")
        button.label = button.fs
    end
    return button
end

local function RefreshList()
    if not listChild then
        return
    end

    ClearButtons()

    local y = -6
    local shown = 0
    for _, item in ipairs(ITEMS) do
        local matched = true
        if searchText ~= "" and ExBoss.UI and ExBoss.UI.SidebarTextContains then
            matched = ExBoss.UI.SidebarTextContains(GetTitle(item), searchText)
                or ExBoss.UI.SidebarTextContains(item.key, searchText)
                or ExBoss.UI.SidebarTextContains(item.moduleKey, searchText)
        end

        if matched then
            local button = AcquireListButton()
            local active = item.key == selectedKey
            button:SetPoint("TOPLEFT", listChild, "TOPLEFT", 10, y)
            button:SetPoint("RIGHT", listChild, "RIGHT", -8, 0)
            if button.label then
                button.label:SetText(GetTitle(item))
            else
                button.fs:SetText(GetTitle(item))
            end
            if ExBoss.UI and ExBoss.UI.ApplySidebarModuleButtonState and button.label then
                ExBoss.UI.ApplySidebarModuleButtonState(button, active, true)
            else
                button.fs:SetTextColor(active and 1 or 0.88, active and 0.82 or 0.88, active and 0.45 or 0.90, 1)
            end
            button:SetScript("OnClick", function()
                selectedKey = item.key
                RefreshList()
                if leftHostFrame and contentHostFrame then
                    Page:Render(leftHostFrame, contentHostFrame)
                end
            end)
            button:Show()
            activeButtons[#activeButtons + 1] = button
            y = y - 32
            shown = shown + 1
        end
    end

    if shown == 0 then
        local empty = AcquireListButton()
        empty:SetPoint("TOPLEFT", listChild, "TOPLEFT", 10, y)
        empty:SetPoint("RIGHT", listChild, "RIGHT", -8, 0)
        if empty.label then
            empty.label:SetText(L["没有匹配项"])
        else
            empty.fs:SetText(L["没有匹配项"])
        end
        if ExBoss.UI and ExBoss.UI.ApplySidebarModuleButtonState and empty.label then
            ExBoss.UI.ApplySidebarModuleButtonState(empty, false, false)
        else
            empty.fs:SetTextColor(0.45, 0.48, 0.55, 1)
        end
        empty:SetScript("OnClick", nil)
        empty:Show()
        activeButtons[#activeButtons + 1] = empty
        y = y - 32
    end

    listChild:SetHeight(math.max(1, -y + 8))
end

local function EnsureUI(leftFrame)
    if leftRoot then
        return
    end

    leftRoot = CreateFrame("Frame", nil, leftFrame)
    leftRoot:SetAllPoints(leftFrame)

    sidebarDivider = EXUI:CreateVisualTexture(leftRoot, EXBORDERFRAME)
    sidebarDivider:SetWidth(1)
    sidebarDivider:SetPoint("TOPRIGHT", leftRoot, "TOPRIGHT", -2, -2)
    sidebarDivider:SetPoint("BOTTOMRIGHT", leftRoot, "BOTTOMRIGHT", -2, 2)
    sidebarDivider:SetColorTexture(0.12, 0.15, 0.20, 0.9)

    if ExBoss.UI and ExBoss.UI.CreateSidebarSearchBox then
        searchBox = ExBoss.UI.CreateSidebarSearchBox(leftRoot, searchText, {
            placeholder = L["搜索模块..."],
            onChanged = function(text)
                local normalized = ExBoss.UI.NormalizeSidebarSearchText and ExBoss.UI.NormalizeSidebarSearchText(text) or tostring(text or "")
                if normalized == searchText then
                    return
                end
                searchText = normalized
                if listScroll and listScroll.SetVerticalScroll then
                    listScroll:SetVerticalScroll(0)
                end
                RefreshList()
            end,
        })
        searchBox:SetPoint("TOPLEFT", leftRoot, "TOPLEFT", 0, -5)
        searchBox:SetPoint("TOPRIGHT", leftRoot, "TOPRIGHT", -22, -5)
    end

    listScroll = CreateFrame("ScrollFrame", nil, leftRoot, "ScrollFrameTemplate")
    if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then
        ExBoss.UI.ApplyModernScrollBarSkin(listScroll)
    end
    listScroll:SetPoint("TOPLEFT", leftRoot, "TOPLEFT", 0, -40)
    listScroll:SetPoint("BOTTOMRIGHT", leftRoot, "BOTTOMRIGHT", -24, 5)

    listChild = CreateFrame("Frame", nil, listScroll)
    listChild:SetSize(340, 1)
    listScroll:SetScrollChild(listChild)
end

function Page:Render(leftFrame, contentFrame)
    if not leftFrame or not contentFrame then
        return
    end

    contentHostFrame = contentFrame
    leftHostFrame = leftFrame
    EnsureUI(leftFrame)

    leftRoot:SetParent(leftFrame)
    leftRoot:ClearAllPoints()
    leftRoot:SetAllPoints(leftFrame)
    leftRoot:Show()

    RefreshList()
    HideEmbeddedPages()

    -- 重置按钮（悬浮在内容区右上角）
    if not resetButton then
        resetButton = CreateFrame("Button", nil, contentFrame, "UIPanelButtonTemplate")
        resetButton:SetSize(100, 22)
        resetButton:SetText(L["重置配置"])
        resetButton:GetFontString():SetTextColor(1, 0.5, 0.5)
        resetButton:SetScript("OnClick", function()
            local item = ITEMS_BY_KEY[selectedKey]
            if not item then return end
            local moduleKey = item.moduleKey
            local hasFn = ExBoss.ResetModuleConfig and ExBoss.ResetModuleConfig[moduleKey]
            if hasFn then
                StaticPopup_Show("EXBOSS_RESET_TOOL_CONFIRM", item.titleKey, nil, moduleKey)
            end
        end)
    end
    resetButton:SetParent(contentFrame)
    resetButton:SetFrameLevel(contentFrame:GetFrameLevel() + 50)
    resetButton:ClearAllPoints()
    resetButton:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", -28, -4)
    resetButton:Show()

    local pageMap = {
        mythiccast       = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.MythicCastPage,
        interrupttracker = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.InterruptTrackerPage,
    }
    local page = pageMap[selectedKey]
    if page and page.Render then
        page:Render(contentFrame)
    elseif contentFrame and contentFrame._placeholder then
        contentFrame._placeholder:SetText(string.format(L["设置页 [%s] — 待开发"], tostring(selectedKey)))
        contentFrame._placeholder:Show()
    end
end

function Page:Hide()
    HideEmbeddedPages()
    if leftRoot then
        leftRoot:Hide()
    end
    if resetButton then
        resetButton:Hide()
    end
end

function Page:SetSelectedKey(key)
    if type(key) ~= "string" or key == "" then
        return
    end
    for _, item in ipairs(ITEMS) do
        if item.key == key then
            selectedKey = key
            break
        end
    end

    if leftRoot and leftRoot:IsShown() then
        RefreshList()
        if leftHostFrame and contentHostFrame then
            Page:Render(leftHostFrame, contentHostFrame)
        end
    end
end
