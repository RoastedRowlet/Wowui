-- =========================================================
-- 一、模块标识与依赖引用 | Module Identity and Dependencies
-- =========================================================
local ExwindTools = _G.ExwindTools
local EXDB = _G.EXDB
if not ExwindTools then return end
local L = (ExwindTools and ExwindTools.L) or setmetatable({}, { __index = function(_, key) return key end })

-- 仅在测试环境生效（统一走 Core 的 IsBeta 判定）
if not ExwindTools.IsBeta then return end

local EXWIND_MODULE_KEY = "ExPTR.MiniTools"
-- 检查模块是否在引擎中注册且处于开启状态
if not ExwindTools:IsModuleEnabled(EXWIND_MODULE_KEY) then return end

-- =========================================================
-- 二、默认配置与配置访问 | Defaults and Configuration Access
-- =========================================================
-- 默认配置
local EXWIND_DEFAULTS = {
    blockFeedback = true,
    autoLearnProf = true,
}
local EX_DB = ExwindTools:GetModuleDB(EXWIND_MODULE_KEY, EXWIND_DEFAULTS)

-- =========================================================
-- 三、GUI 声明 | GUI Declarations
-- =========================================================
-- ========================================================================
-- [布局注册] Grid 设置界面
-- ========================================================================
local function RegisterLayout()
    -- [声明迁移边界：设置页] 仅把原设置控件改为唯一 settings 声明。
    -- key/type、Beta 门禁及反馈/专业按钮 hook 禁止修改。
    local layout = {
        version = 1,
        sections = {
            {
                kind = "settings",
                id = "common",
                title = L["通用设置"],
                description = L["|cff808080* 以上功能仅在 Beta/PTR 环境生效。一键全学按钮会在专业专精页面显示。|r"],
                items = {
                    { key = "blockFeedback", type = "switch", label = L["屏蔽PTR自带反馈框 (Tooltip Issue Reporter)"] },
                    { key = "autoLearnProf", type = "switch", label = L["开启专业专精一键全学按钮"] },
                },
            },
        },
    }
    ExwindTools.UI:RegisterSettingsPage(EXWIND_MODULE_KEY, layout)
end

RegisterLayout()

-- =========================================================
-- 五、业务状态与功能逻辑 | Business State and Logic
-- =========================================================
-- ========================================================================
-- 1. [BlockFeedback] 屏蔽PTR反馈
-- ========================================================================
local function Init_BlockFeedback()
    if not EX_DB.blockFeedback then return end

    local function RunDisableLogic()
        if _G.PTR_IssueReporter then
            if _G.PTR_IssueReporter.HookIntoTooltip then _G.PTR_IssueReporter.HookIntoTooltip = function() end end
            if _G.PTR_IssueReporter.TriggerEvent then _G.PTR_IssueReporter.TriggerEvent = function() end end
            _G.PTR_IssueReporter.InitializePTRTooltips = function() end

            if _G.TooltipDataProcessor and _G.TooltipDataProcessor.AddTooltipPostCall then
                for tooltipType in pairs(_G.Enum.TooltipDataType) do
                    pcall(function() _G.TooltipDataProcessor.RemoveTooltipPostCall(tooltipType) end)
                end
            end

            _G.hooksecurefunc(_G.GameTooltip, "SetUnitAura", function() end)
            _G.hooksecurefunc(_G.GameTooltip, "SetSpellByID", function() end)
            _G.hooksecurefunc(_G.GameTooltip, "SetCurrencyToken", function() end)
            _G.hooksecurefunc(_G.GameTooltip, "SetItemByID", function() end)
        else
            _G.C_Timer.After(1, RunDisableLogic)
        end
    end
    RunDisableLogic()
end

-- ========================================================================
-- 2. [AutoLearnProf] 专业专精一键全学
-- ========================================================================
local function Init_AutoLearnProf()
    if not EX_DB.autoLearnProf then return end

    local function AutoLearnAll(frame)
        local professionID = frame.professionInfo and frame.professionInfo.professionID
        if not professionID then return end

        local configID = _G.C_ProfSpecs.GetConfigIDForSkillLine(professionID)
        local traitTreeIDs = _G.C_ProfSpecs.GetSpecTabIDsForSkillLine(professionID)
        if not configID or configID == 0 then return end

        local changed = true
        local iterations = 0
        while changed and iterations < 40 do
            changed = false
            iterations = iterations + 1

            for _, treeID in _G.ipairs(traitTreeIDs) do
                local tabState = _G.C_ProfSpecs.GetStateForTab(treeID, configID)
                if tabState == _G.Enum.ProfessionsSpecTabState.Unlockable then
                    local tabInfo = _G.C_ProfSpecs.GetTabInfo(treeID)
                    if tabInfo and tabInfo.rootNodeID then
                        _G.C_Traits.PurchaseRank(configID, tabInfo.rootNodeID)
                        changed = true
                    end
                end

                local nodeIDs = _G.C_Traits.GetTreeNodes(treeID)
                for _, nodeID in _G.ipairs(nodeIDs) do
                    local nodeInfo = _G.C_Traits.GetNodeInfo(configID, nodeID)
                    if nodeInfo then
                        if nodeInfo.type == _G.Enum.TraitNodeType.Selection then
                            if #nodeInfo.entryIDs > 0 and (not nodeInfo.activeEntry or nodeInfo.activeEntry.entryID == 0) then
                                _G.C_Traits.SetSelection(configID, nodeID, nodeInfo.entryIDs[1])
                                changed = true
                                nodeInfo = _G.C_Traits.GetNodeInfo(configID, nodeID)
                            end
                        end

                        while nodeInfo and nodeInfo.canPurchaseRank do
                            if _G.C_Traits.PurchaseRank(configID, nodeID) then
                                changed = true
                                nodeInfo = _G.C_Traits.GetNodeInfo(configID, nodeID)
                            else
                                break
                            end
                        end
                    end
                end
            end
        end

        if iterations > 1 then
            _G.C_Traits.CommitConfig(configID)
            print("|cff00ff00[ExwindTools] " .. L["专业专精知识点已一键加满(PTR模式)。"] .. "|r")
        else
            print("|cffffff00[ExwindTools] " .. L["当前没有可加点的专精项。"] .. "|r")
        end
    end

    -- =========================================================
    -- 四、显示、预览与编辑接入 | Display, Preview and Edit Integration
    -- =========================================================
    -- [卡片迁移边界：自定义渲染] 下列按钮注入暴雪专业页面，不是设置页卡片；外部锚点、学习顺序、点击与显隐 hook 禁止修改。
    local function CreateLearnButton()
        local pFrame = _G.ProfessionsFrame
        if not pFrame or not pFrame.SpecPage or not pFrame.SpecPage.ApplyButton then return end
        if _G.ExwindProfAutoLearnBtn then return end

        local btn = _G.CreateFrame("Button", "ExwindProfAutoLearnBtn", pFrame.SpecPage, "MagicButtonTemplate")
        btn:SetSize(120, 24)
        btn:SetPoint("RIGHT", pFrame.SpecPage.ApplyButton, "LEFT", -10, 0)
        btn:SetText(L["一键全学"])
        btn:SetFrameLevel(pFrame.SpecPage.ApplyButton:GetFrameLevel() + 5)

        btn:SetScript("OnClick", function()
            if pFrame.SpecPage:IsVisible() then
                AutoLearnAll(pFrame.SpecPage)
                if pFrame.SpecPage.TreePreview then
                    pFrame.SpecPage.TreePreview:Hide()
                end
            end
        end)

        local function UpdateBtnVisibility()
            local isVisible = (pFrame.SpecPage and pFrame.SpecPage:IsVisible())
            if isVisible then btn:Show() else btn:Hide() end
        end

        pFrame:HookScript("OnShow", UpdateBtnVisibility)
        if pFrame.SpecPage then
            pFrame.SpecPage:HookScript("OnShow", UpdateBtnVisibility)
        end
        _G.hooksecurefunc(pFrame, "SetTab", function()
            _G.C_Timer.After(0.1, UpdateBtnVisibility)
        end)
        UpdateBtnVisibility()
    end

    -- =========================================================
    -- 六、事件订阅与配置刷新 | Events and Configuration Refresh
    -- =========================================================
    if _G.C_AddOns and _G.C_AddOns.IsAddOnLoaded("Blizzard_Professions") then
        CreateLearnButton()
    else
        ExwindTools:RegisterEvent("ADDON_LOADED", "ExPTR_Mini_ProfLearn", function(_, addon)
            if addon == "Blizzard_Professions" then
                CreateLearnButton()
            end
        end)
    end
end

-- =========================================================
-- 七、初始化与启动 | Initialization and Startup
-- =========================================================
-- ========================================================================
-- 初始化
-- ========================================================================
Init_BlockFeedback()
Init_AutoLearnProf()

-- 汇报加载状态
ExwindTools:ReportReady(EXWIND_MODULE_KEY)
