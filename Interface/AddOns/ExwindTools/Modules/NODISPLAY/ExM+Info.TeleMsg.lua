-- [[ 传送喊话模块 ]]
-- { Key = "ExM+Info.TeleMsg", Name = "传送喊话", Desc = "在施放副本传送法术时自动在队伍频道喊话。", Category = 2 },

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI
local EXState = ExwindTools.State
local L = (ExwindTools and ExwindTools.L) or setmetatable({}, { __index = function(_, key) return key end })

-- 1. 识别 Key
local EXWIND_MODULE_KEY = "ExM+Info.TeleMsg"

-- 2. 载入检查
if not ExwindTools:IsModuleEnabled(EXWIND_MODULE_KEY) then return end

local EXDB = _G.EXDB
if not EXDB then return end

-- 3. 数据默认值
local EXWIND_DEFAULTS = {
    teleportShoutText = "[无广告]正在施放%link , 准备传送到\"%name\"",
    shoutTiming = "施法成功", -- 喊话时机: 施法开始 / 施法成功
}
local EX_DB = ExwindTools:GetModuleDB(EXWIND_MODULE_KEY, EXWIND_DEFAULTS)
local DEFAULT_MSG = EXWIND_DEFAULTS.teleportShoutText

-- =========================================================
-- [v4.2] 注册与配置
-- =========================================================

-- Grid 布局
local function EX_RegisterLayout()
    -- 1. 预计算预览字符串（逻辑在外部执行，layout只拿结果）
    local fmt = EX_DB.teleportShoutText or DEFAULT_MSG
    local name = (EXDB.GetLocalizedInstanceNoteName and EXDB:GetLocalizedInstanceNoteName(658)) or L["萨隆矿坑"]
    local link = "|cff71d5ff|Hspell:444222|h[" .. name .. "]|h|r"
    local out = fmt:gsub("%%link", link):gsub("%%name", name)

    local _, classFilename = UnitClass("player")
    local color = C_ClassColor.GetClassColor(classFilename or "WARRIOR")
    local playerColored = "|c" ..
        ((color and color.GenerateHexColor) and color:GenerateHexColor() or "ffffff") .. UnitName("player") .. "|r"

    local previewText = "\n|cffffd100" ..
    L["预览:"] .. "|r\n|cffaaaaff[" .. L["队伍"] .. "] [" .. playerColored .. "]: " .. out .. "|r"

    local layout = {
        { key = "header", type = "header", x = 1, y = 1, w = 200, h = 6, label = L["传送喊话"], labelSize = 25 },
        {
            key = "descInfo",
            type = "description",
            x = 1,
            y = 11,
            w = 196,
            h = 16,
            label = L["|cffffd100变量说明:|r\
  |cff00ff00%link|r  = 法术链接\
  |cff00ff00%name|r = 副本名称"],
            labelSize = 18
        },
        { key = "shoutTiming", type = "dropdown", x = 1, y = 31, w = 46, h = 6, label = L["喊话时机"], items = "施法开始,施法成功" },
        { key = "teleportShoutText", type = "input", x = 1, y = 44, w = 200, h = 6, label = L["自定义喊话内容"] },
        {
            key = "previewLabel",
            type = "description",
            x = 1,
            y = 52,
            w = 200,
            h = 15,
            label = previewText,
            labelSize = 18
        },
        { key = "reset", type = "button", x = 51, y = 31, w = 46, h = 6, label = L["恢复默认喊话"] },
    }

    ExwindTools:RegisterModuleLayout(EXWIND_MODULE_KEY, layout)
end

-- 3. 立即注册
EX_RegisterLayout()

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
    end
end)

local function RefreshActiveSurfaces()
    -- 当前 Grid 控件已经持有写入后的值；这里只重套现有事件订阅。
    if not EXState.InInstance then
        UpdateTelemsgEvent()
    end
end

EXUI:RegisterModuleValueController(EXWIND_MODULE_KEY, { RefreshActiveSurfaces = RefreshActiveSurfaces })

-- 智能生命周期：在副本外时监听，进本后自动注销
ExwindTools:WatchState("InInstance", EXWIND_MODULE_KEY, function(inInstance)
    if inInstance then
        ExwindTools:UnregisterEvent("UNIT_SPELLCAST_START", EXWIND_MODULE_KEY)
        ExwindTools:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED", EXWIND_MODULE_KEY)
    else
        UpdateTelemsgEvent()
    end
end)

-- 初始检查
if not EXState.InInstance then
    UpdateTelemsgEvent()
end

-- 报告模块加载完成
ExwindTools:ReportReady(EXWIND_MODULE_KEY)
