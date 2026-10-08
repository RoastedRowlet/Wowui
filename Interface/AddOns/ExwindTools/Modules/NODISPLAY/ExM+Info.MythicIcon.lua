-- [[ 大米图标增强 ]]
-- { Key = "ExM+Info.MythicIcon", Name = "大米图标增强", Desc = "在大秘境挑战面板图标上即时显示副本简称、最佳层数和评分。", Category = 2 },

-- =========================================================
-- 一、模块标识与依赖引用 | Module Identity and Dependencies
-- =========================================================
local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI
local EXState = ExwindTools.State
local L = (ExwindTools and ExwindTools.L) or setmetatable({}, { __index = function(_, key) return key end })

-- 1. 识别 Key
local EXWIND_MODULE_KEY = "ExM+Info.MythicIcon"

-- 2. 载入检查
if not ExwindTools:IsModuleEnabled(EXWIND_MODULE_KEY) then return end

local EXDB = _G.EXDB

-- =========================================================
-- 五、业务状态与功能逻辑 | Business State and Logic
-- =========================================================
local function EXWIND_GetInstanceMetaByChallengeModeID(mapID)
    mapID = tonumber(mapID) or 0
    if mapID <= 0 or not EXDB then
        return nil
    end
    if EXDB.GetInstanceNoteMetaByChallengeModeID then
        return EXDB:GetInstanceNoteMetaByChallengeModeID(mapID)
    end
    return EXDB.InstanceNoteByChallengeModeID and EXDB.InstanceNoteByChallengeModeID[mapID] or nil
end

local function EXWIND_GetChallengeModeInstances()
    local list = {}
    if not EXDB or not EXDB.InstanceNoteInstanceList then
        return list
    end

    for _, meta in ipairs(EXDB.InstanceNoteInstanceList) do
        local challengeModeID = tonumber(meta.challengeModeID) or 0
        if challengeModeID > 0 then
            list[#list + 1] = meta
        end
    end

    table.sort(list, function(a, b)
        return (tonumber(a.challengeModeID) or 0) < (tonumber(b.challengeModeID) or 0)
    end)

    return list
end

local function EXWIND_GetRawDefaultMapName(mapID)
    local meta = EXWIND_GetInstanceMetaByChallengeModeID(mapID)
    if meta and meta.zhCNShort and meta.zhCNShort ~= "" then
        return meta.zhCNShort
    end
    return nil
end

local function EXWIND_GetLocalizedDefaultMapName(mapID)
    local meta = EXWIND_GetInstanceMetaByChallengeModeID(mapID)
    if meta then
        local locale = GetLocale and GetLocale() or "zhCN"
        if locale == "zhCN" or locale == "zhTW" then
            return meta.zhCNShort or meta.name or tostring(mapID)
        end
        return meta.enUSShort or meta.nameEN or meta.name or tostring(mapID)
    end

    return tostring(mapID)
end

local function EXWIND_BuildDefaultMapNames()
    local names = {}

    for _, meta in ipairs(EXWIND_GetChallengeModeInstances()) do
        local challengeModeID = tonumber(meta.challengeModeID) or 0
        local shortName = meta.zhCNShort
        if challengeModeID > 0 and shortName and shortName ~= "" then
            names[challengeModeID] = shortName
        end
    end

    return names
end

local defaultMapNamesEXWIND = EXWIND_BuildDefaultMapNames()

local function EXWIND_GetSeasonMaps()
    local maps = C_ChallengeMode and C_ChallengeMode.GetMapTable()
    if maps and #maps > 0 then return maps end
    local list = {}
    for id in pairs(defaultMapNamesEXWIND) do table.insert(list, id) end
    table.sort(list)
    return list
end

local function EXWIND_GetBlizzMapName(mapID)
    local name = C_ChallengeMode.GetMapUIInfo(mapID)
    return (name and name ~= "") and name or EXWIND_GetLocalizedDefaultMapName(mapID)
end

-- 3. 数据默认值
-- =========================================================
-- 二、默认配置与配置访问 | Defaults and Configuration Access
-- =========================================================
local EXWIND_DEFAULTS = {
    displayOptions = {
        showBestLevel = true,
        showScore = true,
    },
    levelStyle = {
        a = 1,
        b = 1,
        font = nil,
        g = 1,
        outline = "OUTLINE",
        r = 1,
        shadow = true,
        size = 29,
        x = 0,
        y = -1,
    },
    mapNames = EXWIND_BuildDefaultMapNames(),
    nameStyle = {
        a = 1,
        b = 0.04,
        font = nil,
        g = 0.63,
        outline = "THICKOUTLINE",
        r = 1,
        shadow = true,
        size = 23,
        x = 1,
        y = 29,
    },
    scoreStyle = {
        a = 1,
        b = 0.87843143939972,
        font = nil,
        g = 1,
        outline = "OUTLINE",
        r = 0.80392163991928,
        shadow = false,
        size = 20,
        x = 0,
        y = -27,
    },
}
local EX_DB = ExwindTools:GetModuleDB(EXWIND_MODULE_KEY, EXWIND_DEFAULTS)

-- =========================================================
-- 传送点击层（从 Tooltip 模块迁移）
-- =========================================================
local EXWIND_TeleportSpellMap = {
    [239] = 1254551,
    [556] = 1254555,
    [161] = 1254557,
    [402] = 393273,
    [557] = 1254400,
    [558] = 1254572,
    [560] = 1254559,
    [559] = 1254563,
    [525] = 1216786,
    [499] = 445444,
    [505] = 445414,
    [503] = 445417,
    [542] = 1237215,
    [378] = 354465,
    [392] = 367416,
    [391] = 367416,
    [587] = 1286809,
    [584] = 1286801,
    [585] = 1286804,
    [586] = 1286807,
    [399] = 393256,
    [249] = 1286831,
    [250] = 1286828,
    [588] = 1286812

}

local function EXWIND_IsSpellKnownEXWIND(spellID)
    if not spellID or spellID <= 0 then
        return false
    end
    if C_SpellBook and C_SpellBook.IsSpellKnown and Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player then
        return C_SpellBook.IsSpellKnown(spellID, Enum.SpellBookSpellBank.Player)
    end
    return IsSpellKnown and IsSpellKnown(spellID) or false
end

local function EXWIND_GetTeleportSpellID(mapID)
    if mapID == 161 then
        local faction = UnitFactionGroup and UnitFactionGroup("player") or ""
        local prefer = (faction == "Horde") and 159898 or 1254557
        local fallback = (prefer == 159898) and 1254557 or 159898
        if EXWIND_IsSpellKnownEXWIND(prefer) then
            return prefer
        end
        if EXWIND_IsSpellKnownEXWIND(fallback) then
            return fallback
        end
        return prefer
    end
    return EXWIND_TeleportSpellMap[mapID]
end

-- =========================================================
-- 四、显示、预览与编辑接入 | Display, Preview and Edit Integration
-- =========================================================
-- [卡片迁移边界：自定义渲染] 下列 secure 传送点击层属于挑战面板运行时外部宿主，不是设置页卡片；创建、点击属性、战斗闸门及显隐合同禁止修改。
local function EXWIND_GetTeleportClickLayer(frame)
    if not frame then return nil end
    if frame.__EXWIND_TeleportLayer then
        return frame.__EXWIND_TeleportLayer
    end

    local layer = CreateFrame("Button", nil, frame, "SecureActionButtonTemplate")
    layer:SetAllPoints(frame)
    layer:SetFrameLevel(frame:GetFrameLevel() + 20)
    layer:RegisterForClicks("AnyUp", "AnyDown")
    layer:SetAlpha(0)
    layer:EnableMouse(true)

    layer:SetScript("OnEnter", function()
        local onEnter = frame:GetScript("OnEnter")
        if onEnter then onEnter(frame) end
    end)
    layer:SetScript("OnLeave", function()
        local onLeave = frame:GetScript("OnLeave")
        if onLeave then
            onLeave(frame)
        else
            GameTooltip:Hide()
        end
    end)

    frame.__EXWIND_TeleportLayer = layer
    return layer
end

local function EXWIND_UpdateTeleportClickLayer(frame, mapID)
    if not frame then return end

    if not mapID then
        if frame.__EXWIND_TeleportLayer then
            frame.__EXWIND_TeleportLayer:EnableMouse(false)
            frame.__EXWIND_TeleportLayer:Hide()
        end
        return
    end

    local spellID = EXWIND_GetTeleportSpellID(mapID)
    if not spellID or not EXWIND_IsSpellKnownEXWIND(spellID) then
        if frame.__EXWIND_TeleportLayer then
            frame.__EXWIND_TeleportLayer:EnableMouse(false)
            frame.__EXWIND_TeleportLayer:Hide()
        end
        return
    end

    if InCombatLockdown and InCombatLockdown() then
        return
    end

    local layer = EXWIND_GetTeleportClickLayer(frame)
    layer:SetAttribute("type", "spell")
    layer:SetAttribute("spell", spellID)
    layer:EnableMouse(true)
    layer:Show()
end

-- =========================================================
-- 三、GUI 声明 | GUI Declarations
-- =========================================================
-- =========================================================
-- [v4.2] 注册与配置
-- =========================================================



-- 2. Grid 布局
local function EX_RegisterLayout()
    -- [声明迁移边界：设置页] 仅把原静态项、动态副本简称项和 fontgroup 改为 typed sections。
    -- challengeModeID key、mapNames 绑定、地图枚举顺序、fontgroup 内容及 secure 传送业务禁止修改。
    local layout = {
        version = 1,
        sections = {
            {
                kind = "settings",
                id = "common",
                title = L["通用设置"],
                items = {
                    { key = "showBestLevel", type = "switch", label = L["显示最佳层数 (居中)"], parentKey = "displayOptions" },
                    { key = "showScore", type = "switch", label = L["显示副本评分 (底部)"], parentKey = "displayOptions" },
                },
            },
            {
                kind = "composite",
                id = "name_style",
                title = L["副本名称样式"],
                component = "fontgroup",
                key = "nameStyle",
            },
            {
                kind = "composite",
                id = "level_style",
                title = L["最佳层数样式"],
                component = "fontgroup",
                key = "levelStyle",
            },
            {
                kind = "composite",
                id = "score_style",
                title = L["副本评分样式"],
                component = "fontgroup",
                key = "scoreStyle",
            },
            {
                kind = "settings",
                id = "map_names",
                title = L["副本简称自定义 (留空则使用默认)"],
                items = {},
            },
        },
    }


    local maps = EXWIND_GetChallengeModeInstances()
    for index, meta in ipairs(maps) do
        local challengeModeID = tonumber(meta.challengeModeID) or 0
        local shortName = EXWIND_GetLocalizedDefaultMapName(challengeModeID)

        layout.sections[5].items[#layout.sections[5].items + 1] = {
            key = tostring(challengeModeID),
            type = "input",
            label = string.format("%s (%d)", shortName, challengeModeID),
            parentKey = "mapNames",
            subKey = tostring(challengeModeID),
        }
    end



    EXUI:RegisterSettingsPage(EXWIND_MODULE_KEY, layout)
end

-- 3. 立即注册
EX_RegisterLayout()

-- =========================================================
-- 五、业务状态与功能逻辑 | Business State and Logic
-- =========================================================
-- =========================================================
-- 核心业务逻辑实现
-- =========================================================

-- 前置声明 (Forward Declarations)
local EXWIND_ApplyNames
local EXWIND_NudgeFontsOnce



local function EXWIND_IsAddOnLoaded(name) return C_AddOns.IsAddOnLoaded(name) end
local function EXWIND_LoadAddOn(name) return C_AddOns.LoadAddOn(name) end

local function EXWIND_BuildRatingLookup()
    local lookup = {}
    local summary = C_PlayerInfo.GetPlayerMythicPlusRatingSummary("player")
    if not summary or not summary.runs then return lookup end
    for _, run in ipairs(summary.runs) do
        lookup[run.challengeModeID] = { level = run.bestRunLevel or 0, score = run.mapScore or 0 }
    end
    return lookup
end

-- [卡片迁移边界：自定义渲染] 以下挑战面板 Overlay 是运行时外部宿主，不是设置页卡片；池化、图标顺序、相关 hook 和刷新节流禁止修改。
local ActiveOverlays = {}



local function UpdateText(fs, cfg, overlay, defaultY)
    -- 1. 检查属性是否变更 (逐字段比较，避免字符串拼接产生垃圾)
    if fs._lastFont ~= cfg.font or fs._lastSize ~= cfg.size or fs._lastOutline ~= cfg.outline or fs._lastShadow ~= cfg.shadow then
        EXDB:ApplyFont(fs, cfg, true)
        fs._lastFont = cfg.font
        fs._lastSize = cfg.size
        fs._lastOutline = cfg.outline
        fs._lastShadow = cfg.shadow
    end

    -- 2. 检查位置是否变更
    local targetY = cfg.y or defaultY
    local targetX = cfg.x or 0
    if fs._lastX ~= targetX or fs._lastY ~= targetY then
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", overlay, "CENTER", targetX, targetY)
        fs._lastX = targetX
        fs._lastY = targetY
    end
end

-- 辅助: 应用位置与字体 (提取出来，供实时调用)

local function UpdateOverlayArt(overlay, mapID, rating)
    if not overlay or not mapID then return end

    local name = EX_DB.mapNames[mapID] or EXWIND_GetBlizzMapName(mapID)
    if name == EXWIND_GetRawDefaultMapName(mapID) then
        name = EXWIND_GetLocalizedDefaultMapName(mapID)
    end
    UpdateText(overlay.name, EX_DB.nameStyle, overlay, 7)
    if overlay.name:GetText() ~= name then
        overlay.name:SetText(name)
    end

    if EX_DB.displayOptions.showBestLevel then
        local best = rating[mapID] and rating[mapID].level or 0
        local bestStr = best > 0 and tostring(best) or ""

        UpdateText(overlay.level, EX_DB.levelStyle, overlay, -1)
        if overlay.level:GetText() ~= bestStr then overlay.level:SetText(bestStr) end

        local color = C_ChallengeMode.GetKeystoneLevelRarityColor(best)
        if color then overlay.level:SetTextColor(color.r, color.g, color.b) end
        overlay.level:Show()
    else
        overlay.level:Hide()
    end

    if EX_DB.displayOptions.showScore then
        local score = rating[mapID] and rating[mapID].score or 0
        local scoreStr = score > 0 and tostring(math.floor(score + 0.5)) or ""

        UpdateText(overlay.score, EX_DB.scoreStyle, overlay, -8)
        if overlay.score:GetText() ~= scoreStr then overlay.score:SetText(scoreStr) end

        local color = C_ChallengeMode.GetSpecificDungeonOverallScoreRarityColor(score)
        if color then overlay.score:SetTextColor(color.r, color.g, color.b) end
        overlay.score:Show()
    else
        overlay.score:Hide()
    end
end

-- FIXBW
local function EXWIND_IsBigWigsScoreFont(fs, icon)
    if not fs or not icon or not fs.IsObjectType or not fs:IsObjectType("FontString") then return false end
    if fs == icon.HighestLevel then return false end
    if fs:GetParent() ~= icon then return false end

    local point, relativeTo, relativePoint, x, y = fs:GetPoint(1)
    if point ~= "BOTTOM" or relativeTo ~= icon or relativePoint ~= "BOTTOM" then return false end

    x = x or 0
    y = y or 0
    if math.abs(x) > 0.1 or math.abs(y - 4) > 0.1 then return false end

    return true
end

local function EXWIND_SuppressBigWigsScore(icon)
    if not icon then return end
    if not EXWIND_IsAddOnLoaded("BigWigs") then return end

    local regions = { icon:GetRegions() }
    for i = 1, #regions do
        local region = regions[i]
        if EXWIND_IsBigWigsScoreFont(region, icon) then
            if not region.__EXWIND_FORCE_HIDDEN then
                region.__EXWIND_FORCE_HIDDEN = true
                hooksecurefunc(region, "Show", function(self) self:Hide() end)
            end
            region:SetText("")
            region:SetAlpha(0)
            region:Hide()
        end
    end
end

local function EXWIND_SuppressBigWigsAllIcons()
    if not EXWIND_IsAddOnLoaded("BigWigs") then return end
    if not ChallengesFrame or not ChallengesFrame:IsShown() then return end

    local icons = ChallengesFrame.DungeonIcons
    if not icons or #icons == 0 then return end

    for i = 1, #icons do
        EXWIND_SuppressBigWigsScore(icons[i])
    end
end

local function EXWIND_SuppressBigWigsBurst()
    -- [Fix] 按用户要求：打开框架后 0.01 / 0.03 秒各屏蔽一次，0.1 秒再兜底一次
    if not EXWIND_IsAddOnLoaded("BigWigs") then return end
    if not ChallengesFrame or not ChallengesFrame:IsShown() then return end

    EXWIND_SuppressBigWigsAllIcons()
    C_Timer.After(0.01, EXWIND_SuppressBigWigsAllIcons)
    C_Timer.After(0.03, EXWIND_SuppressBigWigsAllIcons)
    C_Timer.After(0.1, EXWIND_SuppressBigWigsAllIcons)
end

local lastUpdateRate = 0
EXWIND_ApplyNames = function()
    -- [Fix] 防抖动：限制每 0.1 秒最多调用一次。解决 Hook 事件在短时间内频繁触发导致的性能问题
    local now = GetTime()
    if now - lastUpdateRate < 0.1 then return end
    lastUpdateRate = now

    if not ChallengesFrame or not ChallengesFrame:IsShown() then return end

    local icons = ChallengesFrame.DungeonIcons
    if not icons or #icons == 0 then return end

    -- [Fix] 缓存 rating 查询结果，避免每个图标都重新查询
    local rating = EXWIND_BuildRatingLookup()

    -- 确保 Overlay 数量匹配
    for i, frame in ipairs(icons) do
        local overlay = ActiveOverlays[i]

        -- 如果没有 overlay 或者 overlay 的父对象变了，则创建/重置
        if not overlay or overlay:GetParent() ~= frame then
            if overlay then ExwindFactory:Release("MythicIconOverlay", overlay) end
            overlay = ExwindFactory:Acquire("MythicIconOverlay", frame)

            overlay:SetAllPoints(frame)
            -- 传送安全点击层位于图标 FrameLevel + 20。覆盖文字必须在其上方，
            -- 否则分数／层数会被点击层所属的 Frame 层级遮住。
            overlay:SetFrameLevel(frame:GetFrameLevel() + 30)
            overlay.name:SetDrawLayer("OVERLAY", 7)
            overlay.level:SetDrawLayer("OVERLAY", 7)
            overlay.score:SetDrawLayer("OVERLAY", 7)
            -- 让鼠标事件穿透 Overlay，这样原图标的 Tooltip 能正常工作
            overlay:EnableMouse(false)

            overlay:Show()
            ActiveOverlays[i] = overlay



            if frame.HighestLevel and not frame.HighestLevel.__EXWIND_HIDDEN then
                frame.HighestLevel:Hide()
                frame.HighestLevel:SetAlpha(0)
                hooksecurefunc(frame.HighestLevel, "Show", function(self) self:Hide() end)
                frame.HighestLevel.__EXWIND_HIDDEN = true
            end
        end


        if frame.mapID then
            EXWIND_SuppressBigWigsScore(frame)
            UpdateOverlayArt(overlay, frame.mapID, rating)
            EXWIND_UpdateTeleportClickLayer(frame, frame.mapID)
            if frame.Icon then
                frame.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
            overlay:Show()
        else
            EXWIND_UpdateTeleportClickLayer(frame, nil)
            overlay:Hide()
        end
    end


    for i = #icons + 1, #ActiveOverlays do
        ExwindFactory:Release("MythicIconOverlay", ActiveOverlays[i])
        ActiveOverlays[i] = nil
    end
end

_G.Exwind_RefreshMythicNamesEXWIND = EXWIND_ApplyNames

EXWIND_NudgeFontsOnce = function()
    EXWIND_ApplyNames()
end

local function RefreshActiveSurfaces()
    if _G.ChallengesFrame and _G.ChallengesFrame:IsShown() then
        EXWIND_ApplyNames()
    end
end

EXUI:RegisterModuleValueController(EXWIND_MODULE_KEY, { RefreshActiveSurfaces = RefreshActiveSurfaces })

------------------------------------------------------------
-- =========================================================
-- 六、事件订阅与配置刷新 | Events and Configuration Refresh
-- =========================================================
-- 事件与 Hook
------------------------------------------------------------
local function EXWIND_RefreshBurst()
    EXWIND_SuppressBigWigsBurst()
    EXWIND_ApplyNames()
    C_Timer.After(0.1, EXWIND_ApplyNames)
end

local function EXWIND_HookChallenges()
    if not ChallengesFrame then return end
    if ChallengesFrame.__EXWIND_HOOKED then
        EXWIND_RefreshBurst()
        return
    end
    ChallengesFrame.__EXWIND_HOOKED = true

    if type(ChallengesFrame.Update) == "function" then
        hooksecurefunc(ChallengesFrame, "Update", EXWIND_ApplyNames)
    end
    if type(_G.ChallengesFrame_Update) == "function" then
        hooksecurefunc("ChallengesFrame_Update", EXWIND_ApplyNames)
    end

    ChallengesFrame:HookScript("OnShow", EXWIND_RefreshBurst)
    EXWIND_RefreshBurst()
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE")
eventFrame:RegisterEvent("CHALLENGE_MODE_LEADERS_UPDATE")
eventFrame:RegisterEvent("CHALLENGE_MODE_KEYSTONE_RECEPTABLE_OPEN")
eventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "Blizzard_ChallengesUI" then
        EXWIND_HookChallenges()
    elseif event == "PLAYER_ENTERING_WORLD" then
        if not EXWIND_IsAddOnLoaded("Blizzard_ChallengesUI") then
            EXWIND_LoadAddOn("Blizzard_ChallengesUI")
        end
        EXWIND_HookChallenges()
    else
        EXWIND_RefreshBurst()
    end
end)

if PVEFrame then
    PVEFrame:HookScript("OnShow", function()
        if not EXWIND_IsAddOnLoaded("Blizzard_ChallengesUI") then
            EXWIND_LoadAddOn("Blizzard_ChallengesUI")
        end
        EXWIND_HookChallenges()
        EXWIND_RefreshBurst()
    end)
end

if type(_G.PVEFrame_ShowFrame) == "function" then
    hooksecurefunc("PVEFrame_ShowFrame", function(frameType)
        if frameType == "ChallengesFrame" then
            if not EXWIND_IsAddOnLoaded("Blizzard_ChallengesUI") then
                EXWIND_LoadAddOn("Blizzard_ChallengesUI")
            end
            EXWIND_HookChallenges()
            EXWIND_RefreshBurst()
        end
    end)
end

-- =========================================================
-- 七、初始化与启动 | Initialization and Startup
-- =========================================================
-- 报告模块加载完成
ExwindTools:ReportReady(EXWIND_MODULE_KEY)
