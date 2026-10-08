-- =============================================================
-- [[ PVE 信息扩展面板 ]]
-- { Key = "ExTools.PveInfoPanel", Name = "PVE 扩展面板", Desc = "在副本查找器 (PVEFrame) 侧边显示额外信息挂架。", Category = 4 },
-- =============================================================

-- =========================================================
-- 一、模块标识与依赖引用 | Module Identity and Dependencies
-- =========================================================
local ExwindTools = _G.ExwindTools
local EXDB = _G.EXDB
if not ExwindTools then return end
local EXUI = ExwindTools.UI
local L = (ExwindTools and ExwindTools.L) or setmetatable({}, { __index = function(_, key) return key end })

local EXWIND_MODULE_KEY = "ExTools.PveInfoPanel"

-- =============================================================
-- 第一部分：Grid 布局定义
-- =============================================================
-- =========================================================
-- 三、GUI 声明 | GUI Declarations
-- =========================================================
local function EX_RegisterLayout()
    -- [声明迁移边界：设置页] 仅把原设置控件改为唯一 settings 声明。
    -- key/type、PVE 附着字段与自有侧栏的内容顺序/按钮/显隐回调禁止修改。
    local layout = {
        version = 1,
        sections = {
            {
                kind = "settings",
                id = "common",
                title = L["通用设置"],
                description = L["自动依附在 PVE 面板侧边的信息架。"],
                items = {
                    { key = "enabled", type = "switch", label = L["启用模块"] },
                    { key = "side", type = "select", label = L["依附侧"], options = {
                        { value = "LEFT", label = L["左侧"] },
                        { value = "RIGHT", label = L["右侧"] },
                    } },
                    { key = "offsetX", type = "slider", label = L["水平偏移 (X)"], min = -100, max = 100, step = 1 },
                    { key = "offsetY", type = "slider", label = L["垂直偏移 (Y)"], min = -500, max = 500, step = 5 },
                },
            },
        },
    }
    EXUI:RegisterSettingsPage(EXWIND_MODULE_KEY, layout)
end
EX_RegisterLayout()

if not ExwindTools:IsModuleEnabled(EXWIND_MODULE_KEY) then return end

-- =========================================================
-- 二、默认配置与配置访问 | Defaults and Configuration Access
-- =========================================================
local EX_DB = ExwindTools:GetModuleDB(EXWIND_MODULE_KEY, { enabled = true, side = "RIGHT", offsetX = 2, offsetY = 0 })
local mainFrame
local FIXED_WIDTH = 260
local raiderIOHooked

-- =============================================================
-- 第二部分：辅助组件 (勋章化 UI 部件)
-- =============================================================

-- =========================================================
-- 四、显示、预览与编辑接入 | Display, Preview and Edit Integration
-- =========================================================
local function CreateSectionTitle(parent, text, yOfs)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(FIXED_WIDTH - 15, 14)
    container:SetPoint("TOP", parent, "TOP", 0, yOfs)
    local label = container:CreateFontString(nil, "OVERLAY")
    label:SetFont(ExwindTools.MAIN_FONT, 15, "OUTLINE")
    label:SetText(text)
    label:SetTextColor(1, 0.8, 0, 0.95)
    label:SetPoint("CENTER", 0, 0)
    local leftLine = container:CreateTexture(nil, "ARTWORK")
    leftLine:SetHeight(1)
    leftLine:SetPoint("LEFT", 0, 0)
    leftLine:SetPoint("RIGHT", label, "LEFT", -8, 0)
    leftLine:SetColorTexture(1, 0.8, 0, 0.2)
    local rightLine = container:CreateTexture(nil, "ARTWORK")
    rightLine:SetHeight(1)
    rightLine:SetPoint("RIGHT", 0, 0)
    rightLine:SetPoint("LEFT", label, "RIGHT", 8, 0)
    rightLine:SetColorTexture(1, 0.8, 0, 0.2)
    return container
end

local function CreateHeaderIcon(parent, texture, xOfs, labelText, clickFunc)
    local btn = EXUI:CreateButton(parent, 50, 50, "", clickFunc, { compact = true })
    btn:SetSize(50, 50)
    btn:SetPoint("CENTER", parent, "TOP", xOfs, -47)

    -- 阻止 ElvUI 全局扫描给此按钮套皮肤
    btn.IsSkinned = true
    btn.noBackdrop = true

    local icon = btn:CreateTexture(nil, "OVERLAY")
    icon:SetAllPoints()
    icon:SetTexture("Interface\\AddOns\\ExwindCore\\Textures\\" .. texture)
    icon:SetVertexColor(0.85, 0.85, 0.85)
    btn.icon = icon
    local label = btn:CreateFontString(nil, "OVERLAY")
    label:SetFont(ExwindTools.MAIN_FONT, 15, "OUTLINE")
    label:SetPoint("BOTTOM", icon, "BOTTOM", 0, 1)
    label:SetText(labelText)
    label:SetTextColor(1, 0.8, 0)
    -- OnEnter/OnLeave 槽位上有 Core 的悬停画器（HookScript 接的链），
    -- SetScript 会把整条链清掉；这里的图标高亮用 HookScript 与画器共存。
    btn:HookScript("OnEnter", function(self)
        self.icon:SetVertexColor(1, 1, 1)
        self:SetScale(1.05)
    end)
    btn:HookScript("OnLeave", function(self)
        self.icon:SetVertexColor(0.85, 0.85, 0.85)
        self:SetScale(1.0)
    end)
    return btn
end

-- =============================================================
-- 第三部分：核心功能 (数据处理)
-- =============================================================

local function GetBaseAnchorFrame()
    local anchorFrame = _G.PVEFrame

    -- 探测 ElvUI_WindTools
    local wt = _G.WindTools and _G.WindTools[1]
    if wt and wt.GetModule then
        local ll = wt:GetModule("LFGList", true)
        if ll and ll.RightPanel and ll.RightPanel:IsShown() then
            return ll.RightPanel
        end
    end

    -- 兜底兼容逻辑 (如果用户使用了其他名为 WindUI 的插件)
    if _G.WindUI_PveFrame and _G.WindUI_PveFrame:IsShown() then
        return _G.WindUI_PveFrame
    end
    if _G.WindUI_MainFrame and _G.WindUI_MainFrame:IsShown() then
        return _G.WindUI_MainFrame
    end

    return anchorFrame
end

local function GetRaiderIOAnchorFrame()
    local profileTooltip = _G.RaiderIO_ProfileTooltip
    if profileTooltip and profileTooltip:IsShown() then
        return profileTooltip
    end

    local profileAnchor = _G.RaiderIO_ProfileTooltipAnchor
    if profileAnchor and profileAnchor:IsShown() and profileAnchor:GetParent() and profileAnchor:GetParent():IsShown() then
        return profileAnchor
    end
end

local function UpdatePosition()
    if not mainFrame or not mainFrame:IsShown() then return end

    local offX = EX_DB.offsetX or 2
    local offY = EX_DB.offsetY or 0
    local anchorFrame = GetBaseAnchorFrame()
    local raiderIOAnchor = GetRaiderIOAnchorFrame()

    if raiderIOAnchor then
        local anchorRight = anchorFrame and anchorFrame.GetRight and anchorFrame:GetRight()
        local raiderIORight = raiderIOAnchor.GetRight and raiderIOAnchor:GetRight()
        if anchorRight and raiderIORight and raiderIORight > anchorRight then
            offX = offX + (raiderIORight - anchorRight)
        end
    end

    mainFrame:ClearAllPoints()
    mainFrame:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", offX, offY)
    mainFrame:SetPoint("BOTTOMLEFT", anchorFrame, "BOTTOMRIGHT", offX, offY)
    mainFrame:SetWidth(FIXED_WIDTH)
end

-- [联动 Hook] 确保当 Wind工具箱刷新它的面板时，我们也同步刷新位置
-- =========================================================
-- 六、事件订阅与配置刷新 | Events and Configuration Refresh
-- =========================================================
local function HookWindUI()
    local wt = _G.WindTools and _G.WindTools[1]
    if wt and wt.GetModule then
        local ll = wt:GetModule("LFGList", true)
        if ll and ll.UpdateRightPanel then
            _G.hooksecurefunc(ll, "UpdateRightPanel", function()
                _G.C_Timer.After(0.05, UpdatePosition)
            end)
        end
    end
end

local function HookRaiderIO()
    if raiderIOHooked then return end

    local hookedAny = false
    local function HookFrame(frame)
        if not frame or frame.EX_PveInfoPanelHooked then
            return
        end
        frame.EX_PveInfoPanelHooked = true
        frame:HookScript("OnShow", function()
            _G.C_Timer.After(0.02, UpdatePosition)
        end)
        frame:HookScript("OnHide", function()
            _G.C_Timer.After(0.02, UpdatePosition)
        end)
        hookedAny = true
    end

    HookFrame(_G.RaiderIO_ProfileTooltip)
    HookFrame(_G.RaiderIO_ProfileTooltipAnchor)

    if hookedAny then
        raiderIOHooked = true
    end
end

local function GetChallengeModeMeta(challengeModeID)
    challengeModeID = tonumber(challengeModeID) or 0
    if challengeModeID <= 0 or not EXDB then
        return nil
    end
    if EXDB.GetInstanceNoteMetaByChallengeModeID then
        return EXDB:GetInstanceNoteMetaByChallengeModeID(challengeModeID)
    end
    return EXDB.InstanceNoteByChallengeModeID and EXDB.InstanceNoteByChallengeModeID[challengeModeID] or nil
end

local function GetChallengeModeShortName(challengeModeID)
    local meta = GetChallengeModeMeta(challengeModeID)
    if meta then
        local locale = GetLocale and GetLocale() or "zhCN"
        if locale == "zhCN" or locale == "zhTW" then
            return meta.zhCNShort or meta.name or tostring(challengeModeID)
        end
        return meta.enUSShort or meta.nameEN or meta.name or tostring(challengeModeID)
    end

    local name = _G.C_ChallengeMode.GetMapUIInfo(challengeModeID)
    return name or tostring(challengeModeID)
end

-- =========================================================
-- 五、业务状态与功能逻辑 | Business State and Logic
-- =========================================================
local function UpdateStats()
    if not mainFrame or not mainFrame:IsShown() then return end

    -- 获取本周战绩
    local wRuns = _G.C_MythicPlus.GetRunHistory(false, true, true) or {}
    table.sort(wRuns, function(a, b) return a.level > b.level end)

    local mapTable = _G.C_ChallengeMode.GetMapTable() or {}
    local aggregatedData = {}
    for _, id in ipairs(mapTable) do aggregatedData[id] = { highest = 0, runs = {} } end

    for _, run in ipairs(wRuns) do
        local id = run.mapChallengeModeID
        if aggregatedData[id] then
            if run.level > aggregatedData[id].highest then aggregatedData[id].highest = run.level end
            table.insert(aggregatedData[id].runs, { level = run.level, timed = run.completed })
        end
    end



    -- 2. 上半部
    local upper = ""
    for i = 1, 8 do
        local run = wRuns[i]
        if run then
            local name, _, _, icon = _G.C_ChallengeMode.GetMapUIInfo(run.mapChallengeModeID)
            local hex = "ffffffff"
            local mix = _G.C_ChallengeMode.GetKeystoneLevelRarityColor(run.level)
            if mix then hex = mix:GenerateHexColor() or "ffffffff" end

            upper = upper .. string.format("%s |cffffffff+%d|r |c%s%s|r\n",
                _G.CreateSimpleTextureMarkup(icon or 136116, 14, 14), run.level, hex, name or "??")
        else
            upper = upper .. "|cff444444-|r\n"
        end
    end
    mainFrame.upperDisplay:SetText(upper:gsub("\n$", ""))

    -- 2. 下半部
    local lower = ""
    for _, id in ipairs(mapTable) do
        local _, _, _, icon = _G.C_ChallengeMode.GetMapUIInfo(id)
        local data = aggregatedData[id]
        local runsStr = ""
        if data and #data.runs > 0 then
            table.sort(data.runs, function(a, b) return b.level < a.level end)
            for _, r in ipairs(data.runs) do
                runsStr = runsStr .. (r.timed and "|cff00ff00" or "|cffff0000") .. r.level .. "|r "
            end
        else
            runsStr = "|cff888888-|r"
        end
        local iconMarkup = _G.CreateSimpleTextureMarkup(icon or 136116, 14, 14)
        local nameOverlay = string.format("|cffffd100%s|r", GetChallengeModeShortName(id))
        lower = lower .. string.format("%s %s (%s)\n", iconMarkup, nameOverlay, runsStr)
    end
    mainFrame.lowerDisplay:SetText(lower:gsub("\n$", ""))
end

-- 整套 UI 已加载时只使用本模块自己的普通黑色半透明背景，不调用第三方皮肤 API。
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

-- [卡片迁移边界：自定义渲染] 下列 PVE 侧栏是运行时独立窗口，不是设置页卡片内容；禁止借设置迁移改其固定尺寸、段落顺序、入口按钮或显隐逻辑。
local function CreateMainFrame()
    if mainFrame then return end

    local hasLoadedUIReplacement = ExwindTools:HasLoadedUIReplacement()

    if hasLoadedUIReplacement then
        -- 整套 UI 模式：创建纯净窗口并使用本模块黑色半透明背景。
        mainFrame = CreateFrame("Frame", "ExPveInfoPanel_Final", UIParent)
        mainFrame:SetSize(FIXED_WIDTH, 540)

        local title = mainFrame:CreateFontString(nil, "OVERLAY")
        title:SetFont(ExwindTools.MAIN_FONT, 16, "OUTLINE")
        title:SetPoint("TOP", 0, -8)
        title:SetTextColor(1, 0.82, 0)
        mainFrame.TitleText = title

        local close = EXUI:CreatePicButton(mainFrame, 24, 24,
            "Interface\\Buttons\\UI-Panel-CloseButton-Up",
            "Interface\\Buttons\\UI-Panel-CloseButton-Down",
            "Interface\\Buttons\\UI-Panel-CloseButton-Highlight",
            function() mainFrame:Hide() end, true)
        close:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -2, -2)
        mainFrame.CloseButton = close

        ApplyLoadedUIBackdrop(mainFrame)
    else
        -- [暴雪模式]：直接使用原生模板，不进行任何皮肤篡改
        mainFrame = CreateFrame("Frame", "ExPveInfoPanel_Final", UIParent, "DefaultPanelTemplate")
        mainFrame:SetSize(FIXED_WIDTH, 540)
    end

    mainFrame:SetFrameStrata("MEDIUM")
    mainFrame:SetToplevel(true)

    -- 保障标题文字
    if mainFrame.TitleText then mainFrame.TitleText:SetText(L["本周大秘境信息"]) end

    -- 顶部按钮：位置固化，仅对调“统计”与“赛季”
    mainFrame.infoBtn = CreateHeaderIcon(mainFrame, "ExInfo.png", -75, L["法术"],
        function() if SlashCmdList["EXSP"] then SlashCmdList["EXSP"]() end end)
    mainFrame.vaultBtn = CreateHeaderIcon(mainFrame, "ExVault.png", 0, L["大米"],
        function() if SlashCmdList["EXMPLUS"] then SlashCmdList["EXMPLUS"]() end end)
    mainFrame.statBtn = CreateHeaderIcon(mainFrame, "ExTotal.png", 75, L["记录"],
        function() if _G.EXMYRUN then _G.EXMYRUN:ToggleWindow() end end)

    -- 分割线 1 (低保记录)：下移以避开图标
    CreateSectionTitle(mainFrame, L["本周低保记录"], -75)
    local d1 = mainFrame:CreateFontString(nil, "OVERLAY")
    d1:SetFont(ExwindTools.MAIN_FONT, 15, "OUTLINE")
    d1:SetPoint("TOPLEFT", 15, -92)
    d1:SetJustifyH("LEFT")
    d1:SetSpacing(2)
    mainFrame.upperDisplay = d1

    -- 分割线 2 (大米详情)：下浮对应高度
    CreateSectionTitle(mainFrame, L["本周大米详情"], -251)
    local d2 = mainFrame:CreateFontString(nil, "OVERLAY")
    d2:SetFont(ExwindTools.MAIN_FONT, 15, "OUTLINE")
    d2:SetPoint("TOPLEFT", 15, -267)
    d2:SetJustifyH("LEFT")
    d2:SetSpacing(1)
    mainFrame.lowerDisplay = d2

    mainFrame:Hide()
    -- 判断面板是否应该显示
    local function ShouldShow()
        if not EX_DB.enabled then return false end
        if not _G.PVEFrame or not _G.PVEFrame:IsShown() then return false end

        -- 1: GroupFinder (LFG), 2: PVP, 3: Challenges (PVE/Mythic+)
        -- 根据用户要求，仅在切到 PVE (大秘境/挑战) 分页时显示
        local activeTab = _G.PanelTemplates_GetSelectedTab(_G.PVEFrame)
        if activeTab == 3 then
            return true
        end
        return false
    end

    local function UpdateVisibility()
        if not mainFrame then return end
        if ShouldShow() then
            mainFrame:Show()
            UpdatePosition()
            UpdateStats()
        else
            mainFrame:Hide()
        end
    end

    local function HookPVE()
        if not _G.PVEFrame then return end
        if _G.EXMRH_LaunchButton then _G.EXMRH_LaunchButton:Hide() end
        if _G.EXMRH_SpellInfoButton then _G.EXMRH_SpellInfoButton:Hide() end

        -- 挂钩显示与隐藏脚本
        _G.PVEFrame:HookScript("OnShow", function()
            _G.C_Timer.After(0.1, UpdateVisibility)
        end)
        _G.PVEFrame:HookScript("OnHide", function()
            if mainFrame then mainFrame:Hide() end
        end)

        -- 关键：挂钩暴雪分页切换函数
        if _G.PVEFrame_ShowFrame then
            _G.hooksecurefunc("PVEFrame_ShowFrame", UpdateVisibility)
        end

        -- 初始检测
        UpdateVisibility()
    end
    if _G.PVEFrame then
        HookPVE()
        HookWindUI()
        HookRaiderIO()
        ExwindTools:RegisterEvent("ADDON_LOADED", EXWIND_MODULE_KEY .. ".RaiderIO",
            function(_, n)
                if n == "RaiderIO" then
                    _G.C_Timer.After(0.2, function()
                        HookRaiderIO()
                        UpdatePosition()
                    end)
                end
            end)
    else
        ExwindTools:RegisterEvent("ADDON_LOADED", EXWIND_MODULE_KEY,
            function(_, n)
                if n == "Blizzard_GroupFinder" then
                    HookPVE()
                    HookWindUI()
                    HookRaiderIO()
                elseif n == "RaiderIO" then
                    _G.C_Timer.After(0.2, function()
                        HookRaiderIO()
                        UpdatePosition()
                    end)
                end
            end)
    end
end

local function RefreshPanelDisplay()
    if mainFrame and mainFrame:IsShown() then
        -- side/offset 配置与当前可见宿主同属显示投影；刷新须同步重算位置。
        UpdatePosition()
        UpdateStats()
    end
end

local function RefreshActiveSurfaces()
    if not EX_DB.enabled then
        if mainFrame then mainFrame:Hide() end
        return
    end
    RefreshPanelDisplay()
end

-- =========================================================
-- 六、事件订阅与配置刷新 | Events and Configuration Refresh — Runtime Subscriptions / 运行时订阅
-- =========================================================
EXUI:RegisterModuleValueController(EXWIND_MODULE_KEY, { RefreshActiveSurfaces = RefreshActiveSurfaces })

ExwindTools:RegisterEvent("ITEM_CHANGED", EXWIND_MODULE_KEY, RefreshPanelDisplay)
ExwindTools:RegisterEvent("BAG_UPDATE_DELAYED", EXWIND_MODULE_KEY, RefreshPanelDisplay)
ExwindTools:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE", EXWIND_MODULE_KEY, RefreshPanelDisplay)
ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", EXWIND_MODULE_KEY, function()
    _G.C_Timer.After(0.3, function()
        if mainFrame then
            RefreshPanelDisplay()
        end
    end)
end)

-- =========================================================
-- 七、初始化与启动 | Initialization and Startup
-- =========================================================
C_Timer.After(1, function() if EX_DB.enabled then CreateMainFrame() end end)
ExwindTools:ReportReady(EXWIND_MODULE_KEY)
