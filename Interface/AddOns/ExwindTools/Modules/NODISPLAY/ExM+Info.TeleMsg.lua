-- [[ 传送喊话模块 ]]
-- { Key = "ExM+Info.TeleMsg", Name = "传送喊话", Desc = "在施放副本传送法术时自动在队伍频道喊话。", Category = 2 },

-- =========================================================
-- 一、模块标识与依赖引用 | Module Identity and Dependencies
-- =========================================================
local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI
local L = (ExwindTools and ExwindTools.L) or setmetatable({}, { __index = function(_, key) return key end })

-- 1. 识别 Key
local EXWIND_MODULE_KEY = "ExM+Info.TeleMsg"

-- 2. 载入检查
if not ExwindTools:IsModuleEnabled(EXWIND_MODULE_KEY) then return end

local EXDB = _G.EXDB
if not EXDB then return end

-- 3. 数据默认值
-- =========================================================
-- 二、默认配置与配置访问 | Defaults and Configuration Access
-- =========================================================
local EXWIND_DEFAULTS = {
    teleportShoutText = "[无广告]正在施放%link , 准备传送到\"%name\"",
    shoutTiming = "施法成功", -- 喊话时机: 施法开始 / 施法成功
}
local EX_DB = ExwindTools:GetModuleDB(EXWIND_MODULE_KEY, EXWIND_DEFAULTS)
local DEFAULT_MSG = EXWIND_DEFAULTS.teleportShoutText

-- =========================================================
-- 三、GUI 声明 | GUI Declarations
-- =========================================================
-- =========================================================
-- [v4.2] 注册与配置
-- =========================================================

-- Grid 布局
local function BuildPreviewText()
    local fmt = EX_DB.teleportShoutText or DEFAULT_MSG
    local name = (EXDB.GetLocalizedInstanceNoteName and EXDB:GetLocalizedInstanceNoteName(658)) or L["萨隆矿坑"]
    local link = "|cff71d5ff|Hspell:444222|h[" .. name .. "]|h|r"
    local out = fmt:gsub("%%link", link):gsub("%%name", name)

    local _, classFilename = UnitClass("player")
    local color = C_ClassColor.GetClassColor(classFilename or "WARRIOR")
    local playerColored = "|c" ..
        ((color and color.GenerateHexColor) and color:GenerateHexColor() or "ffffff") .. UnitName("player") .. "|r"

    return "\n|cffffd100" ..
        L["预览:"] .. "|r\n|cffaaaaff[" .. L["队伍"] .. "] [" .. playerColored .. "]: " .. out .. "|r"
end

local function BuildPreviewSection()
    return {
        kind = "table", id = "preview", title = L["变量与预览"],
        columns = { { title = "" } }, supportsAdd = false,
        records = {
            { cells = { { text = L["|cffffd100变量说明:|r\
  |cff00ff00%link|r  = 法术链接\
  |cff00ff00%name|r = 副本名称"] } } },
            { cells = { { text = BuildPreviewText() } } },
        },
    }
end

local function EX_RegisterLayout()
    local layout = {
        version = 1,
        sections = {
            {
                kind = "settings",
                id = "common",
                title = L["喊话设置"],
                items = {
                    {
                        key = "shoutTiming", type = "select", label = L["喊话时机"],
                        options = {
                            { value = "施法开始", label = L["施法开始"] },
                            { value = "施法成功", label = L["施法成功"] },
                        },
                    },
                    { key = "reset", type = "button", label = L["恢复默认喊话"] },
                    { key = "teleportShoutText", type = "input", label = L["自定义喊话内容"],
                        inputWidthPercent = 200 },
                },
            },
            BuildPreviewSection(),
        },
    }

    EXUI:RegisterSettingsPage(EXWIND_MODULE_KEY, layout)
end

-- 3. 立即注册
EX_RegisterLayout()

local function GetVisibleSettingsSession()
    if EXUI.CurrentPage ~= "ModuleSettings" or EXUI.CurrentModule ~= EXWIND_MODULE_KEY then return nil end
    local page = EXUI.ActivePageFrame
    return page and page._exCardSession or nil
end

local function RefreshVisibleText(resetInput)
    local session = GetVisibleSettingsSession()
    if not session then return end
    if resetInput then
        local input = session:GetWidget("common", "teleportShoutText")
        if input then input:SetText(EX_DB.teleportShoutText or DEFAULT_MSG) end
    end
    session:ReplaceSettingsSection("preview", BuildPreviewSection())
end

-- =========================================================
-- 五、业务状态与功能逻辑 | Business State and Logic
-- =========================================================
-- =========================================================
-- 业务逻辑
-- =========================================================

-- 通用喊话处理（施法开始和施法成功共用）
local function HandleSpellCast(unit, spellID)
    if unit ~= "player" then return end
    local dungeonName = EXDB.SpellToDungeonName[spellID]
    -- 通天峰：联盟/部落法术 ID 兼容
    if not dungeonName and (spellID == 159898 or spellID == 1254557) then
        dungeonName = "通天峰"
    end
    if not dungeonName then return end

    local dungeonMeta = EXDB.GetInstanceNoteMetaByName and EXDB:GetInstanceNoteMetaByName(dungeonName)
    dungeonName = (dungeonMeta and EXDB.GetLocalizedInstanceNoteName and EXDB:GetLocalizedInstanceNoteName(dungeonMeta)) or
        dungeonName

    local spellLink = C_Spell.GetSpellLink(spellID)
    if not spellLink then return end

    local msgFormat = EX_DB.teleportShoutText or DEFAULT_MSG
    local message = msgFormat:gsub("%%link", spellLink):gsub("%%name", dungeonName)
    SendChatMessage(message, "PARTY")
end

local function OnSpellStart(event, unit, _, spellID)
    HandleSpellCast(unit, spellID)
end

local function OnSpellSucceeded(event, unit, _, spellID)
    HandleSpellCast(unit, spellID)
end

-- =========================================================
-- 六、事件订阅与配置刷新 | Events and Configuration Refresh
-- =========================================================
-- 根据当前设置注册对应的事件，注销另一个
local function UpdateTelemsgEvent()
    local timing = EX_DB.shoutTiming or EXWIND_DEFAULTS.shoutTiming
    if timing == "施法开始" then
        ExwindTools:RegisterEvent("UNIT_SPELLCAST_START", EXWIND_MODULE_KEY, OnSpellStart)
        ExwindTools:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED", EXWIND_MODULE_KEY)
    else
        -- 默认：施法成功
        ExwindTools:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", EXWIND_MODULE_KEY, OnSpellSucceeded)
        ExwindTools:UnregisterEvent("UNIT_SPELLCAST_START", EXWIND_MODULE_KEY)
    end
end

-- 4. 绑定逻辑
ExwindTools:WatchState(EXWIND_MODULE_KEY .. ".ButtonClicked", EXWIND_MODULE_KEY, function(data)
    if data.key == "reset" then
        EX_DB.teleportShoutText = DEFAULT_MSG
        EXUI:NotifyModuleValueChanged(EXWIND_MODULE_KEY, "teleportShoutText", "committed")
        RefreshVisibleText(true)
    end
end)

local function RefreshActiveSurfaces(_, changedPath)
    UpdateTelemsgEvent()
    if changedPath == "teleportShoutText" then RefreshVisibleText(false) end
end

EXUI:RegisterModuleValueController(EXWIND_MODULE_KEY, { RefreshActiveSurfaces = RefreshActiveSurfaces })

-- =========================================================
-- 七、初始化与启动 | Initialization and Startup
-- =========================================================
UpdateTelemsgEvent()

-- 报告模块加载完成
ExwindTools:ReportReady(EXWIND_MODULE_KEY)
