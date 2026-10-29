-- =============================================================
-- [[ 全职业延迟容限 ]]
-- { Key = "ExTools.SpellQueue", Name = "全职业延迟容限", Desc = "根据当前专精自动调整输入延迟容限(SpellQueueWindow)。", Category = 5 },
-- =============================================================

-- =========================================================
-- 一、模块标识与依赖引用 | Module Identity and Dependencies
-- =========================================================
local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI
local L = (ExwindTools and ExwindTools.L) or setmetatable({}, { __index = function(_, key) return key end })
local EXState = ExwindTools.State

-- =============================================================
-- 第一部分：模块标识与载入检查
-- =============================================================
local EXWIND_MODULE_KEY = "ExTools.SpellQueue"

if not ExwindTools:IsModuleEnabled(EXWIND_MODULE_KEY) then return end

-- =============================================================
-- 第二部分：依赖与数据初始化
-- =============================================================
local EXDB = _G.EXDB
if not EXDB then return end

-- =========================================================
-- 二、默认配置与配置访问 | Defaults and Configuration Access
-- =========================================================
local EXWIND_DEFAULTS = {
    enabled = false,
    aiMode = false,
    globalFixed = 400,
    globalOffset = 0,
    specs = {},   -- 固定模式：每个专精的固定延迟值
    specsAI = {}, -- AI 模式：每个专精的偏移值
}
local EX_DB = ExwindTools:GetModuleDB(EXWIND_MODULE_KEY, EXWIND_DEFAULTS)


local function GetCurrentInfo()
    local s = EXState
    local curV = GetCVar("SpellQueueWindow") or "400"
    local cHex = "ffffff"
    if s.ClassID and EXDB.Classes[s.ClassID] then cHex = EXDB.Classes[s.ClassID].colorHex end
    local sIcon = (s.SpecID and EXDB.SpecByID[s.SpecID]) and EXDB.SpecByID[s.SpecID].icon or 0
    local iStr = sIcon > 0 and string.format("|T%d:14:14:0:0|t ", sIcon) or ""
    return string.format(L["当前: %s|cff%s%s - %s|r | 系统值: |cffffd100%sms|r"], iStr, cHex, s.ClassName or L["未知"],
        s.SpecName or L["未知"], curV)
end

local function MakeSpecLabel(icon, colorHex, specName)
    return string.format("|T%d:14:14:0:0|t |cff%s%s|r", icon, colorHex, L[specName])
end

local SPEC_GROUPS = {
    plate = {
        { class = "死亡骑士", specs = { { 250, 135770, "C41E3A", "鲜血" }, { 251, 135773, "C41E3A", "冰霜" }, { 252, 135775, "C41E3A", "邪恶" } } },
        { class = "战士", specs = { { 73, 132341, "C79C6E", "防护" }, { 71, 132355, "C79C6E", "武器" }, { 72, 132347, "C79C6E", "狂怒" } } },
        { class = "圣骑士", specs = { { 66, 236264, "F48CBA", "防护" }, { 70, 135873, "F48CBA", "惩戒" }, { 65, 135920, "F48CBA", "神圣" } } },
    },
    mail = {
        { class = "猎人", specs = { { 255, 461113, "ABD473", "生存" }, { 254, 236179, "ABD473", "射击" }, { 253, 461112, "ABD473", "野兽控制" } } },
        { class = "萨满祭司", specs = { { 262, 136048, "0070DD", "元素" }, { 263, 237581, "0070DD", "增强" }, { 264, 136052, "0070DD", "恢复" } } },
        { class = "唤魔师", specs = { { 1467, 4511811, "33937F", "湮灭" }, { 1473, 5198700, "33937F", "增辉" }, { 1468, 4511812, "33937F", "恩护" } } },
    },
    leather = {
        { class = "恶魔猎手", specs = { { 581, 1247265, "A330C9", "复仇" }, { 577, 1247264, "A330C9", "浩劫" }, { 1480, 7455385, "A330C9", "噬灭" } } },
        { class = "潜行者", specs = { { 260, 236286, "FFF468", "狂徒" }, { 259, 236270, "FFF468", "奇袭" }, { 261, 132320, "FFF468", "敏锐" } } },
        { class = "武僧", specs = { { 268, 608951, "00FF98", "酒仙" }, { 269, 608953, "00FF98", "踏风" }, { 270, 608952, "00FF98", "织雾" } } },
        { class = "德鲁伊", specs = { { 104, 132276, "FF7C0A", "守护" }, { 103, 132115, "FF7C0A", "野性" }, { 102, 136096, "FF7C0A", "平衡" }, { 105, 136041, "FF7C0A", "恢复" } } },
    },
    cloth = {
        { class = "法师", specs = { { 64, 135846, "3FC7EB", "冰霜" }, { 63, 135810, "3FC7EB", "火焰" }, { 62, 135932, "3FC7EB", "奥术" } } },
        { class = "术士", specs = { { 267, 136186, "8788EE", "毁灭" }, { 265, 136145, "8788EE", "痛苦" }, { 266, 136172, "8788EE", "恶魔学识" } } },
        { class = "牧师", specs = { { 256, 135940, "FFFFFF", "戒律" }, { 257, 237542, "FFFFFF", "神圣" }, { 258, 136207, "FFFFFF", "暗影" } } },
    },
}

-- =========================================================
-- 三、GUI 声明 | GUI Declarations
-- =========================================================
-- 一个职业一行：左职业名，右每个专精“图标+名称”加输入框；AI 与固定模式各一行，按模式显示。
local function BuildSpecCard(id, title, source)
    local children = {}
    for index, class in ipairs(SPEC_GROUPS[source]) do
        for _, mode in ipairs({ { "specs", "fixedMode", "" }, { "specsAI", "aiMode", "|cff00ffff(AI)|r " } }) do
            local storageKey = mode[1]
            local rowId = id .. ".row" .. index .. "." .. storageKey
            local specs = {}
            for slot, spec in ipairs(class.specs) do
                -- 专精名定宽，各职业的“名称 + 输入框”组才能上下对齐。
                specs[#specs + 1] = { id = rowId .. ".label" .. slot, kind = "text",
                    text = mode[3] .. MakeSpecLabel(spec[2], spec[3], spec[4]), width = mode[3] == "" and 84 or 116 }
                specs[#specs + 1] = { id = rowId .. ".spec" .. slot, kind = "control", controlType = "input",
                    path = storageKey .. "." .. spec[1], width = 64 }
            end
            children[#children + 1] = { id = rowId, kind = "setting", label = L[class.class], visible = mode[2],
                children = specs }
        end
    end
    return { id = id, kind = "card", title = title, children = children }
end

local function BuildV2Declaration()
    return {
        version = 2,
        freeform = "ExTools.SpellQueue", -- Core 例外名单：本页按行对齐，不走标准设置行
        cards = {
            {
                id = "queue.core", kind = "card", title = L["全职业延迟容限 (SpellQueueWindow)"], children = {
                    { id = "live_status", kind = "hint", textSource = "status" },
                    { id = "queue.help", kind = "hint", text = L["AI模式：容限 = 延迟 + 偏移。固定模式：容限 = 设定值。"] },
                    { id = "enabled", kind = "control", path = "enabled", controlType = "switch", label = L["开启功能"] },
                    { id = "aiMode", kind = "control", path = "aiMode", controlType = "switch", label = "|cff00ffff" .. L["启用 AI 智能模式"] .. "|r" },
                    { id = "globalFixed", kind = "control", path = "globalFixed", controlType = "input", label = L["全局默认延迟值 (固定)"], visible = "fixedMode" },
                    { id = "globalOffset", kind = "control", path = "globalOffset", controlType = "input", label = L["全局延迟偏移 |cff00ffff(AI)|r"], visible = "aiMode" },
                },
            },
            BuildSpecCard("queue.plate", L["板甲职业"], "plate"),
            BuildSpecCard("queue.mail", L["锁甲职业"], "mail"),
            BuildSpecCard("queue.leather", L["皮甲职业"], "leather"),
            BuildSpecCard("queue.cloth", L["布甲职业"], "cloth"),
        },
    }
end

local function CreateV2Owner()
    local owner = {
        binding = { moduleKey = EXWIND_MODULE_KEY, config = EX_DB },
        texts = {}, predicates = {},
    }
    owner.texts.status = function() return GetCurrentInfo() end
    owner.predicates.aiMode = function() return EX_DB.aiMode == true end
    owner.predicates.fixedMode = function() return EX_DB.aiMode ~= true end
    return owner
end

local layoutRegistered = false
local function EX_RegisterLayout()
    if layoutRegistered then return end
    EXUI:RegisterModuleSettingsPageV2(EXWIND_MODULE_KEY, BuildV2Declaration(), CreateV2Owner)
    layoutRegistered = true
end

-- =========================================================
-- 五、业务状态与功能逻辑 | Business State and Logic
-- =========================================================
local function ApplySpellQueue()
    if not EX_DB.enabled then return end

    local state = EXState
    local specID = state.SpecID
    if not specID or specID == 0 then return end

    local storage = EX_DB.aiMode and EX_DB.specsAI or EX_DB.specs
    -- 读取分离后的全局变量
    local defaultVal = EX_DB.aiMode and EX_DB.globalOffset or EX_DB.globalFixed
    local val = storage[specID] or defaultVal or 400

    local finalVal = tonumber(val) or 400

    if EX_DB.aiMode then
        local _, _, _, lagWorld = GetNetStats()
        lagWorld = lagWorld or 0
        if lagWorld < 300 then
            finalVal = lagWorld + finalVal
        end
    end

    finalVal = math.max(0, math.min(400, finalVal))
    SetCVar("SpellQueueWindow", finalVal)
end

-- =========================================================
-- 六、事件订阅与配置刷新 | Events and Configuration Refresh
-- =========================================================
-- =============================================================
-- 第四部分：事件与状态订阅
-- =============================================================
local function RefreshActiveSurfaces()
    ApplySpellQueue()
    local page = EXUI:GetModulePage(EXWIND_MODULE_KEY)
    if page then page:Refresh() end
end

EXUI:RegisterModuleValueController(EXWIND_MODULE_KEY, { RefreshActiveSurfaces = RefreshActiveSurfaces })

-- 监听天赋/职业变动 (核心框架广播)
local function OnIdentityChanged()
    RefreshActiveSurfaces()
end

ExwindTools:WatchState("SpecID", EXWIND_MODULE_KEY, OnIdentityChanged)
ExwindTools:WatchState("ClassName", EXWIND_MODULE_KEY, OnIdentityChanged)
ExwindTools:WatchState("SpecName", EXWIND_MODULE_KEY, OnIdentityChanged)

-- =============================================================
-- 第五部分：初始化与模块报告
-- =============================================================
-- =========================================================
-- 七、初始化与启动 | Initialization and Startup
-- =========================================================
C_Timer.After(2, ApplySpellQueue)

ExwindTools:ReportReady(EXWIND_MODULE_KEY)

-- =============================================================
-- 第六部分：首次注册
-- =============================================================
EX_RegisterLayout()
