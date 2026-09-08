-- [[ 大秘境伤害计算模块 ]]
-- { Key = "ExM+.MythicDamage", Name = "大秘境伤害计算", Desc = "根据层数计算法术实际伤害数值。", Category = 2 },

local ExwindTools = _G.ExwindTools
local EXDB = _G.EXDB
if not ExwindTools then return end
local EXUI = ExwindTools.UI
local L = (ExwindTools and ExwindTools.L) or setmetatable({}, { __index = function(_, key) return key end })
local EXState = ExwindTools.State

-- 1. 识别 Key
local EXWIND_MODULE_KEY = "ExM+.MythicDamage"

-- 2. 载入检查
if not ExwindTools:IsModuleEnabled(EXWIND_MODULE_KEY) then return end

-- 3. 数据初始化
local EXWIND_DEFAULTS = {
    mythicLevel = 10,
    useColoredNumbers = true,
    abbreviateNumbers = true,
    damageColorR = 0.01,
    damageColorG = 1,
    damageColorB = 0.79,
}
local EX_DB = ExwindTools:GetModuleDB(EXWIND_MODULE_KEY, EXWIND_DEFAULTS)

-- =========================================================
-- 核心业务逻辑 (需提前定义供 Layout 使用)
-- =========================================================
local EXMD = { EX_DB = EX_DB }
_G.EXMD = EXMD

local SEASON_BASE_FACTORS = { [34] = 1.8945719251 }
local function GetBaseFactor() return SEASON_BASE_FACTORS[C_SeasonInfo.GetCurrentDisplaySeasonID()] or 1 end
local MYTHIC_BOSS_EXTRA_MULTIPLIER = 1.15
local MYTHIC_TRASH_EXTRA_MULTIPLIER = 1.2

local EXCLUDE_UNITS = { ["码"] = true, ["秒"] = true, ["个"] = true, ["%"] = true, ["人"] = true, ["阶"] = true }

local function FormatLargeNumber(v)
    if v >= 100000000 then
        return string.format(L["%.2f亿"], v / 100000000)
    elseif v >= 10000 then
        return string.format(L["%d万"], math.floor(v / 10000))
    else
        return tostring(math.floor(v))
    end
end

function EXMD.IsBossMobData(mobData)
    return type(mobData) == "table" and tonumber(mobData.level) == 92
end

function EXMD.GetCurrentMultiplier(mobData)
    local level = EX_DB.mythicLevel or 0
    local data = _G.EXDB and _G.EXDB.MythicDamageData
    if not data then return 1 end

    local baseMulti = data.LevelMultipliers[level] or (level >= 25 and data.LevelMultipliers[25] or 1)

    -- 10 层以上应用额外加成：BOSS 与小怪分开计算
    if level >= 10 then
        baseMulti = baseMulti *
            (EXMD.IsBossMobData(mobData) and MYTHIC_BOSS_EXTRA_MULTIPLIER or MYTHIC_TRASH_EXTRA_MULTIPLIER)
    end

    -- 返回最终倍率 (包含赛季基数)
    local finalMulti = baseMulti * GetBaseFactor()
    -- 如果计算出来层数很低且没有倍率（比如 1），则返回 1 避免后续修改
    return finalMulti > 1 and finalMulti or 1
end

function EXMD.ProcessDamageText(text, multiplier)
    if not text or not multiplier or multiplier <= 1 then return text end

    local db = _G.EXTOOLS12S2 and _G.EXTOOLS12S2.ModuleDB and _G.EXTOOLS12S2.ModuleDB["ExM+.MythicDamage"] or EX_DB
    local r, g, b = db.damageColorR or 1, db.damageColorG or 0.82, db.damageColorB or 0
    local useColor = db.useColoredNumbers
    local abbreviate = db.abbreviateNumbers

    local hex = string.format("%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))

    -- 法术描述数字已含玩家全能增伤，需先除掉再乘层数倍率
    local versa = (EXState and EXState.PStat_Versa) or 0
    local correctedMultiplier = multiplier / (1 + versa / 100)

    -- 查找文本中的数字
    return text:gsub("([%d,，%.]+)(%%?)", function(numStr, percent)
        if percent == "%" then return numStr .. percent end

        local value = tonumber(numStr:gsub("[,，]", ""), 10)
        -- 仅放大真正的伤害/治疗类大数字，避免把能量、层数、秒数等小数值也改掉
        if not value or value < 10000 then return numStr end

        -- 检查文本中数字后的第一个字符是否为禁用单位
        local pos = text:find(numStr, 1, true)
        if pos then
            local nextChar = text:sub(pos + #numStr, pos + #numStr + 2)
            if EXCLUDE_UNITS[nextChar] then
                return numStr
            end
        end

        local nv = math.floor(value * correctedMultiplier)
        local f = abbreviate and FormatLargeNumber(nv) or
            tostring(nv):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")

        return useColor and ("|cff" .. hex .. f .. "|r") or f
    end)
end

-- =========================================================
-- [v4.2] 注册与配置
-- =========================================================

-- 1. Grid 布局
local function EX_RegisterLayout()
    local level = EX_DB.mythicLevel or 10
    local multi = EXMD and EXMD.GetCurrentMultiplier and EXMD.GetCurrentMultiplier() or 1
    local seasonID = C_SeasonInfo.GetCurrentDisplaySeasonID()
    local descLabel = string.format(
        L["当前层数: |cffffd100%d|r\n当前赛季(ID:%d)系数: |cffffd100%.2f|r\n最终计算倍率: |cff00ff00%.2f|r\n\n开启功能后，法术说明中的数字将根据倍率实时调整。"],
        level, seasonID, 1.76, multi
    )

    local layout = {
        { key = "header", type = "header", x = 1, y = 4, w = 200, h = 3, label = L["大秘境伤害计算"], labelSize = 25 },
        { key = "desc", type = "description", x = 1, y = 12, w = 200, h = 8, label = L["法术描述的数值会随着层数改变"] },
        { key = "useColoredNumbers", type = "checkbox", x = 1, y = 23, w = 46, h = 6, label = L["数值染色"] },
        { key = "mythicLevel", type = "slider", x = 2, y = 39, w = 46, h = 6, label = L["模拟层数 (0-30)"], min = 0, max = 30 },
        { key = "damageColor", type = "color", x = 52, y = 39, w = 46, h = 6, label = L["伤害数值颜色"] },
        { key = "openSpellInfo", type = "button", x = 116, y = 24, w = 55, h = 10, label = L["大米怪物法术"] },
        { key = "abbreviateNumbers", type = "checkbox", x = 51, y = 23, w = 46, h = 6, label = L["简写数字 (万/亿)"] },
    }


    ExwindTools:RegisterModuleLayout(EXWIND_MODULE_KEY, layout)
end

-- 3. 立即注册
EX_RegisterLayout()

local function RefreshActiveSurfaces()
    -- 当前 Grid 控件已经持有写入后的值；这里只重套已存在的法术手册面板。
    if _G.EXSP and _G.EXSP.LevelSlider then
        local level = EX_DB.mythicLevel or 10
        if _G.EXSP.LevelSlider:GetValue() ~= level then _G.EXSP.LevelSlider:SetValue(level) end
    end
    if _G.EXSP and _G.EXSP.RefreshRightPanel then _G.EXSP:RefreshRightPanel() end
end

EXUI:RegisterModuleValueController(EXWIND_MODULE_KEY, { RefreshActiveSurfaces = RefreshActiveSurfaces })

-- 监听按钮点击
ExwindTools:WatchState(EXWIND_MODULE_KEY .. ".ButtonClicked", EXWIND_MODULE_KEY, function(data)
    if data.key == "openSpellInfo" then
        if SlashCmdList["EXSP"] then SlashCmdList["EXSP"]() end
    end
end)

-- 报告模块加载完成
ExwindTools:ReportReady(EXWIND_MODULE_KEY)
