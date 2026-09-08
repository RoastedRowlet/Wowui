-- [[ BETA 大米钥石 ]]
-- { Key = "ExPTR.SetKey", Name = "BETA 大米钥石", Desc = "快速设置钥石等级与地图，并显示当前拥有的钥石信息。", Category = 3 },

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI
local L = (ExwindTools and ExwindTools.L) or setmetatable({}, { __index = function(_, key) return key end })

-- 1. 识别 Key
local EXWIND_MODULE_KEY = "ExPTR.SetKey"

-- 仅在测试环境生效（统一走 Core 的 IsBeta 判定）
if not ExwindTools.IsBeta then return end

-- 2. 载入检查
if not ExwindTools:IsModuleEnabled(EXWIND_MODULE_KEY) then return end

local FIXED_WIDTH = 280
local mainFrame
local EXDB = _G.EXDB

-- 3. 数据初始化
local EX_DEFAULTS = {
    current = {
        a = 1,
        b = 1,
        current_iconSize = 75,
        g = 0,
        groupX = -2,
        groupY = -1,
        iconSize = 34,
        iconX = 10,
        iconY = -17,
        outline = "THICKOUTLINE",
        r = 0.83,
        shadow = false,
        shadowX = 1,
        shadowY = -1,
        size = 30,
        x = 6,
        y = -9,
    },
    enabled = true,
    iconsX = 21,
    iconsY = -52,
    level = {
        a = 1,
        b = 0.92,
        g = 1,
        groupX = -13,
        groupY = 4,
        iconSize = 40,
        level_groupX = 62,
        level_groupY = -25,
        level_iconSize = 73,
        level_spacingX = 72,
        level_spacingY = 62,
        outline = "THICKOUTLINE",
        r = 0.91,
        shadow = false,
        shadowX = 1,
        shadowY = -1,
        size = 32,
        spacingX = 47,
        spacingY = 44,
        x = 0,
        y = 0,
    },
    map = {
        a = 1,
        b = 0.26274511218071,
        g = 0.74901962280273,
        groupX = -12,
        groupY = -1,
        iconSize = 48,
        map_groupX = 46,
        map_groupY = -62,
        map_iconSize = 68,
        map_spacingX = 126,
        map_spacingY = 130,
        outline = "THICKOUTLINE",
        r = 1,
        shadow = true,
        shadowX = 1,
        shadowY = -1,
        size = 20,
        spacingX = 60,
        spacingY = 58,
        x = 2,
        y = 12,
    },
    offsetX = -6,
    offsetY = 0,
    side = "LEFT",
    currentIconStyle = { width = 34, height = 34, showIcon = true, showBorder = false, borderTexture = "EX_Default", borderSize = 0, borderPadding = 0.6, borderColorR = 0, borderColorG = 0, borderColorB = 0, borderColorA = 1, reverse = false, x = 0, y = 0 },
    levelIconStyle = { width = 40, height = 40, showIcon = true, showBorder = false, borderTexture = "EX_Default", borderSize = 0, borderPadding = 0.6, borderColorR = 0, borderColorG = 0, borderColorB = 0, borderColorA = 1, reverse = false, x = 0, y = 0 },
    mapIconStyle = { width = 48, height = 48, showIcon = true, showBorder = false, borderTexture = "EX_Default", borderSize = 0, borderPadding = 0.6, borderColorR = 0, borderColorG = 0, borderColorB = 0, borderColorA = 1, reverse = false, x = 0, y = 0 },
}

local EX_DB = ExwindTools:GetModuleDB(EXWIND_MODULE_KEY, EX_DEFAULTS)

local function GetIconDimensions(styleKey, legacyTable)
    local style = EX_DB[styleKey]
    if type(style) ~= "table" then
        style = { width = legacyTable.iconSize, height = legacyTable.iconSize, showIcon = true }
        EX_DB[styleKey] = style
    end
    return math.max(16, tonumber(style.width) or legacyTable.iconSize or 32),
        math.max(16, tonumber(style.height) or legacyTable.iconSize or 32), style
end

-- =============================================================
-- 第一部分：Grid 布局定义
-- =============================================================
local function EX_RegisterLayout()
    local layout = {
        { key = "header", type = "header", x = 1, y = 4, w = 188, h = 8, label = L["BETA 大米制作挂架"] },
        { key = "desc", type = "description", x = 1, y = 12, w = 188, h = 4, label = L["自动依附在 PVE 面板左侧的快速设钥架。"] },
        { key = "enabled", type = "checkbox", x = 1, y = 20, w = 48, h = 8, label = L["启用模块"] },
        { key = "side", type = "select", x = 56, y = 20, w = 48, h = 8, label = L["依附侧"], options = { ["LEFT"] = L["左侧"], ["RIGHT"] = L["右侧"] } },
        { key = "offsetX", type = "slider", x = 1, y = 40, w = 60, h = 8, label = L["整体 X 偏移"], min = -100, max = 100, step = 1 },
        { key = "offsetY", type = "slider", x = 72, y = 40, w = 60, h = 8, label = L["整体 Y 偏移"], min = -500, max = 500, step = 5 },

        { key = "sub_global", type = "subheader", x = 1, y = 52, w = 188, h = 4, label = L["图标整体偏移 (不建议动框架, 动这个)"] },
        { key = "iconsX", type = "slider", x = 1, y = 60, w = 60, h = 8, label = L["图标组 X"], min = -100, max = 100, step = 1 },
        { key = "iconsY", type = "slider", x = 72, y = 60, w = 60, h = 8, label = L["图标组 Y"], min = -100, max = 100, step = 1 },

        { key = "sub_cur", type = "subheader", x = 1, y = 72, w = 188, h = 4, label = L["当前显示"] },
        { key = "groupX", type = "slider", x = 1, y = 80, w = 60, h = 8, label = L["模块 X"], min = -100, max = 100, parentKey = "current" },
        { key = "groupY", type = "slider", x = 72, y = 80, w = 60, h = 8, label = L["模块 Y"], min = -100, max = 100, parentKey = "current" },
        { key = "current", type = "fontgroup", x = 1, y = 104, w = 200, h = 50, label = L["当前文字设置"] },

        { key = "sub_level", type = "subheader", x = 1, y = 180, w = 188, h = 4, label = L["等级按钮"] },
        { key = "groupX", type = "slider", x = 1, y = 188, w = 60, h = 8, label = L["模块 X"], min = -100, max = 100, parentKey = "level" },
        { key = "groupY", type = "slider", x = 72, y = 188, w = 60, h = 8, label = L["模块 Y"], min = -100, max = 100, parentKey = "level" },
        { key = "spacingX", type = "slider", x = 72, y = 200, w = 60, h = 8, label = L["横向间距"], min = 20, max = 100, parentKey = "level" },
        { key = "level", type = "fontgroup", x = 1, y = 212, w = 200, h = 50, label = L["数字字体设置"] },

        { key = "sub_map", type = "subheader", x = 1, y = 288, w = 188, h = 4, label = L["地图按钮"] },
        { key = "groupX", type = "slider", x = 1, y = 296, w = 60, h = 8, label = L["模块 X"], min = -100, max = 100, parentKey = "map" },
        { key = "groupY", type = "slider", x = 72, y = 296, w = 60, h = 8, label = L["模块 Y"], min = -100, max = 100, parentKey = "map" },
        { key = "spacingX", type = "slider", x = 72, y = 308, w = 60, h = 8, label = L["横向间距"], min = 20, max = 120, parentKey = "map" },
        { key = "spacingY", type = "slider", x = 1, y = 320, w = 60, h = 8, label = L["纵向间距"], min = 20, max = 120, parentKey = "map" },
        { key = "map", type = "fontgroup", x = 1, y = 332, w = 200, h = 50, label = L["副本字体设置"] },
        { key = "currentIconStyle", type = "icongroup", x = 1, y = 412, w = 200, h = 50, label = L["当前图标"], labelSize = 20, opts = { enableOffset = false } },
        { key = "levelIconStyle", type = "icongroup", x = 1, y = 512, w = 200, h = 50, label = L["等级图标"], labelSize = 20, opts = { enableOffset = false } },
        { key = "mapIconStyle", type = "icongroup", x = 1, y = 612, w = 200, h = 50, label = L["地图图标"], labelSize = 20, opts = { enableOffset = false } },
    }
    ExwindTools:RegisterModuleLayout(EXWIND_MODULE_KEY, layout)
end
EX_RegisterLayout()

-- =============================================================
-- 第二部分：整套 UI 兼容背景
-- =============================================================

local function ApplyLoadedUIBackdrop(frame)
    if not frame or not ExwindTools:HasLoadedUIReplacement() then return false end
    local backdrop = frame._exLoadedUIBackdrop
    if not backdrop then
        backdrop = frame:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints(frame)
        frame._exLoadedUIBackdrop = backdrop
    end
    backdrop:SetColorTexture(0, 0, 0, 0.8)
    return true
end

-- =============================================================
-- 第三部分：核心功能 (位置维护与显示更新)
-- =============================================================

local function UpdatePosition()
    if not mainFrame or not mainFrame:IsShown() then return end

    local anchorFrame = _G.PVEFrame
    mainFrame:ClearAllPoints()

    local side = EX_DB.side or "LEFT"
    local offX = EX_DB.offsetX or (side == "LEFT" and -2 or 2)
    local offY = EX_DB.offsetY or 0

    if side == "LEFT" then
        mainFrame:SetPoint("TOPRIGHT", anchorFrame, "TOPLEFT", offX, offY)
        mainFrame:SetPoint("BOTTOMRIGHT", anchorFrame, "BOTTOMLEFT", offX, offY)
    else
        mainFrame:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", offX, offY)
        mainFrame:SetPoint("BOTTOMLEFT", anchorFrame, "BOTTOMRIGHT", offX, offY)
    end
    mainFrame:SetWidth(FIXED_WIDTH)
end

local function UpdateCurrentKeystone()
    if not mainFrame then return end
    local mapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID()
    local level = C_MythicPlus.GetOwnedKeystoneLevel()

    local db = EX_DB.current
    EXDB:ApplyFont(mainFrame.currentText, db)
    local iconWidth, iconHeight = GetIconDimensions("currentIconStyle", db)
    mainFrame.currentIcon:SetSize(iconWidth, iconHeight)
    mainFrame.currentIcon:SetPoint("LEFT", mainFrame, "TOPLEFT", db.iconX + EX_DB.iconsX + db.groupX,
        db.iconY + 15 + EX_DB.iconsY + db.groupY) -- 位置上移
    mainFrame.currentText:SetPoint("LEFT", mainFrame.currentIcon, "RIGHT", db.x, db.y)

    if mapID and level and mapID > 0 and level > 0 then
        local name, _, _, textureID = C_ChallengeMode.GetMapUIInfo(mapID)
        mainFrame.currentText:SetText(string.format("%s(%d)", name or "??", level))
        mainFrame.currentIcon:SetTexture(textureID or 463531)
    else
        mainFrame.currentText:SetText("|cff888888" .. L["制作钥石"] .. "|r")
        mainFrame.currentIcon:SetTexture(463531)
    end
end

local function RebuildButtons()
    if not mainFrame then return end

    -- 等级按钮
    local keystoneLevels = { 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 }
    local dbL = EX_DB.level
    local levelWidth, levelHeight = GetIconDimensions("levelIconStyle", dbL)
    local keystoneItemIDs = { 166381, 166380, 166379, 166378, 166377, 159694, 159695, 159696, 159697, 159698 }
    for i, b in ipairs(mainFrame.levelBtns) do
        local row = (i <= 5) and 0 or 1
        local col = (i - 1) % 5
        b:SetSize(levelWidth, levelHeight)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 20 + col * dbL.spacingX + dbL.groupX + EX_DB.iconsX,
            -50 - row * dbL.spacingY + dbL.groupY + EX_DB.iconsY)

        EXDB:ApplyFont(b.txt, dbL)
        b.txt:SetPoint("CENTER", b, "CENTER", dbL.x, dbL.y)
        b.txt:SetText(keystoneLevels[i])
        b:SetAttribute("macrotext", "/use item:" .. keystoneItemIDs[i] .. "\n/use item:151086")
    end

    -- 地图按钮
    local dbM = EX_DB.map
    local mapWidth, mapHeight = GetIconDimensions("mapIconStyle", dbM)
    local mapData = {
        { name = L["密谋"], cmID = 587, itemID = 271947 },
        { name = L["夺目"], cmID = 584, itemID = 271960 },
        { name = L["虚空"], cmID = 585, itemID = 271952 },
        { name = L["洞穴"], cmID = 586, itemID = 271958 },
        { name = L["红玉"], cmID = 399, itemID = 201350 },
        { name = L["诸王"], cmID = 249, itemID = 166391 },
        { name = L["神庙"], cmID = 250, itemID = 166394 },
        { name = L["毒牙"], cmID = 588, itemID = 271944 },
    }
    for i, b in ipairs(mainFrame.mapBtns) do
        local row = math.floor((i - 1) / 4)
        local col = (i - 1) % 4
        b:SetSize(mapWidth, mapHeight)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 18 + col * dbM.spacingX + dbM.groupX + EX_DB.iconsX,
            -150 - row * dbM.spacingY + dbM.groupY + EX_DB.iconsY)

        local _, _, _, tex = C_ChallengeMode.GetMapUIInfo(mapData[i].cmID)
        b:SetNormalTexture(tex or 463531)
        if b:GetNormalTexture() then b:GetNormalTexture():SetTexCoord(0.08, 0.92, 0.08, 0.92) end

        EXDB:ApplyFont(b.txt, dbM)
        b.txt:SetPoint("CENTER", b, "CENTER", dbM.x, dbM.y)
        b.txt:SetText(mapData[i].name)
        b:SetAttribute("macrotext", "/use item:" .. mapData[i].itemID .. "\n/use item:151086")
    end

    UpdateCurrentKeystone()
end

-- =============================================================
-- 第四部分：框架生成
-- =============================================================

local function CreateMainFrame()
    if mainFrame then return end

    local hasLoadedUIReplacement = ExwindTools:HasLoadedUIReplacement()

    if hasLoadedUIReplacement then
        mainFrame = _G.CreateFrame("Frame", "ExPTR_SetKey_SidePanel", _G.UIParent)
        mainFrame:SetSize(FIXED_WIDTH, 480)
        local title = mainFrame:CreateFontString(nil, "OVERLAY")
        title:SetFont(ExwindTools.MAIN_FONT, 15, "OUTLINE")
        title:SetPoint("TOP", 0, -8)
        title:SetTextColor(1, 0.82, 0)
        title:SetText(L["BETA 钥石挂架"])
        mainFrame.TitleText = title
        local close = _G.CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -2, -2)
        mainFrame.CloseButton = close
        ApplyLoadedUIBackdrop(mainFrame)
    else
        mainFrame = _G.CreateFrame("Frame", "ExPTR_SetKey_SidePanel", _G.UIParent, "DefaultPanelTemplate")
        mainFrame:SetSize(FIXED_WIDTH, 480)
        if mainFrame.TitleText then
            mainFrame.TitleText:SetText(L["BETA 钥石挂架"])
            mainFrame.TitleText:SetFont(ExwindTools.MAIN_FONT, 14, "OUTLINE")
        end
    end

    mainFrame:SetFrameStrata("MEDIUM")
    mainFrame:SetToplevel(true)

    -- 1. 当前显示组件
    mainFrame.currentIcon = mainFrame:CreateTexture(nil, "ARTWORK")
    mainFrame.currentIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    mainFrame.currentText = mainFrame:CreateFontString(nil, "OVERLAY")

    -- 2. 等级按钮组
    mainFrame.levelBtns = {}
    local keystoneItemIDs = { 166381, 166380, 166379, 166378, 166377, 159694, 159695, 159696, 159697, 159698 }
    for i = 1, 10 do
        local b = _G.CreateFrame("Button", nil, mainFrame, "SecureActionButtonTemplate, UIPanelButtonTemplate")
        b:RegisterForClicks("AnyUp", "AnyDown")
        b:SetAttribute("type", "macro")
        b:SetAttribute("macrotext", "/use item:" .. keystoneItemIDs[i] .. "\n/use item:151086")
        b:SetNormalTexture(463531)
        if b:GetNormalTexture() then b:GetNormalTexture():SetTexCoord(0.08, 0.92, 0.08, 0.92) end
        b.txt = b:CreateFontString(nil, "OVERLAY")
        table.insert(mainFrame.levelBtns, b)
    end

    -- 3. 地图按钮组
    mainFrame.mapBtns = {}
    local mapData = {
        { name = L["密谋"], cmID = 587, itemID = 271947 },
        { name = L["夺目"], cmID = 584, itemID = 271960 },
        { name = L["虚空"], cmID = 585, itemID = 271952 },
        { name = L["洞穴"], cmID = 586, itemID = 271958 },
        { name = L["红玉"], cmID = 399, itemID = 201350 },
        { name = L["诸王"], cmID = 249, itemID = 166391 },
        { name = L["神庙"], cmID = 250, itemID = 166394 },
        { name = L["毒牙"], cmID = 588, itemID = 271944 },
    }
    for i, data in ipairs(mapData) do
        local b = _G.CreateFrame("Button", nil, mainFrame, "SecureActionButtonTemplate, UIPanelButtonTemplate")
        b:RegisterForClicks("AnyUp", "AnyDown")
        b:SetAttribute("type", "macro")
        b:SetAttribute("macrotext", "/use item:" .. data.itemID .. "\n/use item:151086")
        b.txt = b:CreateFontString(nil, "OVERLAY")
        b.data = data
        table.insert(mainFrame.mapBtns, b)
    end

    mainFrame:Hide()

    -- 判断面板是否应该显示
    local function ShouldShow()
        if not EX_DB.enabled then return false end
        if not _G.PVEFrame or not _G.PVEFrame:IsShown() then return false end

        -- 1: GroupFinder (LFG), 2: PVP, 3: Challenges (PVE/Mythic+)
        -- BETA 钥石挂架仅在 M+ 挑战分页显示
        local activeTab = _G.PanelTemplates_GetSelectedTab(_G.PVEFrame)
        return (activeTab == 3)
    end

    local function UpdateVisibility()
        if not mainFrame then return end
        if ShouldShow() then
            mainFrame:Show()
            UpdatePosition()
            RebuildButtons()
        else
            mainFrame:Hide()
        end
    end

    local function HookPVE()
        if not _G.PVEFrame then return end

        -- 挂钩显示与隐藏脚本
        _G.PVEFrame:HookScript("OnShow", function()
            _G.C_Timer.After(0.1, UpdateVisibility)
        end)
        _G.PVEFrame:HookScript("OnHide", function()
            if mainFrame then mainFrame:Hide() end
        end)

        -- 挂钩分页切换
        if _G.PVEFrame_ShowFrame then
            _G.hooksecurefunc("PVEFrame_ShowFrame", UpdateVisibility)
        end

        -- 初始检测
        UpdateVisibility()
    end

    if _G.PVEFrame then
        HookPVE()
    else
        ExwindTools:RegisterEvent("ADDON_LOADED", EXWIND_MODULE_KEY, function(_, n)
            if n == "Blizzard_GroupFinder" then HookPVE() end
        end)
    end
end

-- =============================================================
-- 第五部分：监听与响应
-- =============================================================

local function OnDataUpdate()
    if mainFrame and mainFrame:IsShown() then _G.C_Timer.After(0.2, RebuildButtons) end
end

ExwindTools:RegisterEvent("ITEM_CHANGED", EXWIND_MODULE_KEY, OnDataUpdate)
ExwindTools:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE", EXWIND_MODULE_KEY, OnDataUpdate)
ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", EXWIND_MODULE_KEY, function()
    if mainFrame then RebuildButtons() end
end)

local function RefreshActiveSurfaces()
    if not EX_DB.enabled then
        if mainFrame then mainFrame:Hide() end
        return
    end
    if mainFrame then
        UpdatePosition()
        RebuildButtons()
    end
end

EXUI:RegisterModuleValueController(EXWIND_MODULE_KEY, { RefreshActiveSurfaces = RefreshActiveSurfaces })

_G.C_Timer.After(1.5, function()
    if EX_DB.enabled then CreateMainFrame() end
end)

ExwindTools:ReportReady(EXWIND_MODULE_KEY)
