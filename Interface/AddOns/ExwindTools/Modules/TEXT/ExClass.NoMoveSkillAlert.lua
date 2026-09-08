-- =============================================================
-- [[ 位移技能CD提示 (No Move Skill Alert) ]]
-- =============================================================

local ExwindTools = _G.ExwindTools
local EXDB = _G.EXDB
-- 本模块的 Panel/World/Runtime 三宿主全部依赖 EXUI。加载顺序异常时必须整体
-- 停止，不能像旧实现一样留下 EXUI=nil 并在打开设置页时崩溃。
if not ExwindTools or not ExwindTools.UI then return end
local EXUI = ExwindTools.UI
local L = (ExwindTools and ExwindTools.L) or setmetatable({}, { __index = function(_, key) return key end })

local MODULE_KEY = "ExClass.NoMoveSkillAlert"
local DEFAULT_ALERT_OFFSET_X, DEFAULT_ALERT_OFFSET_Y = 15, -5
local RefreshActiveSurfaces

-- =============================================================
-- 声明式配置：只维护职业 / 专精 / 法术ID / 显示文本Key
-- =============================================================
local NO_MOVE_SKILL_CONFIGS = {
    MAGE = {
        header = "法师设置",
        color = "3fc7eb",
        mode = "KNOWN_FIRST",
        displayRows = {
            { specIDs = { 62, 63, 64 }, enabledKey = "mage_enable", formatKey = "displayFormat", defaultFormat = "我没有闪 (%t)" },
        },
        candidates = {
            { spellID = 212653, enabledKey = "mage_enable", formatKey = "displayFormat" }, -- 闪光术
            { spellID = 1953,   enabledKey = "mage_enable", formatKey = "displayFormat" }, -- 闪现
        },
    },
    DEATHKNIGHT = {
        header = "死亡骑士设置",
        color = "c41e3a",
        mode = "KNOWN_FIRST",
        displayRows = {
            { specIDs = { 250, 251, 252 }, enabledKey = "dk_enable_steed", formatKey = "dk_fmt_steed", defaultFormat = "没有骑马 (%t)" },
        },
        candidates = {
            { spellID = 444347, enabledKey = "dk_enable_steed", formatKey = "dk_fmt_steed" }, -- 骑马
            { spellID = 48265,  enabledKey = "dk_enable_steed", formatKey = "dk_fmt_steed" }, -- 死亡脚步
        },
    },
    ROGUE = {
        header = "盗贼设置",
        color = "fff468",
        mode = "SPEC",
        displayRows = {
            { specIDs = { 259, 261 }, enabledKey = "rogue_enable_shadow",  formatKey = "rogue_fmt_shadow" },
            { specIDs = { 260 },      enabledKey = "rogue_enable_phantom", formatKey = "rogue_fmt_phantom" },
        },
        specs = {
            [259] = { spellID = 36554, enabledKey = "rogue_enable_shadow", formatKey = "rogue_fmt_shadow", defaultFormat = "没有影步 (%t)" },
            [260] = { spellID = 195457, enabledKey = "rogue_enable_phantom", formatKey = "rogue_fmt_phantom", defaultFormat = "没有爪钩 (%t)" },
            [261] = { spellID = 36554, enabledKey = "rogue_enable_shadow", formatKey = "rogue_fmt_shadow", defaultFormat = "没有影步 (%t)" },
        },
        order = { 259, 260, 261 },
    },
    PALADIN = {
        header = "圣骑士设置",
        color = "f48cba",
        mode = "SPEC",
        displayRows = {
            { specIDs = { 65 }, enabledKey = "paladin_enable_holy",        formatKey = "paladin_fmt_holy" },
            { specIDs = { 66 }, enabledKey = "paladin_enable_protection",  formatKey = "paladin_fmt_protection" },
            { specIDs = { 70 }, enabledKey = "paladin_enable_retribution", formatKey = "paladin_fmt_retribution" },
        },
        specs = {
            [65] = {
                spellID = 190784,
                enabledKey = "paladin_enable_holy",
                formatKey = "paladin_fmt_holy",
                defaultFormat = "没有骑马 (%t)",
            },
            [66] = {
                spellID = 190784,
                enabledKey = "paladin_enable_protection",
                formatKey = "paladin_fmt_protection",
                fallbackFormatKey = "paladin_fmt_steed",
                defaultFormat = "没有骑马 (%t)",
            },
            [70] = {
                spellID = 190784,
                enabledKey = "paladin_enable_retribution",
                formatKey = "paladin_fmt_retribution",
                defaultFormat = "没有骑马 (%t)",
            },
        },
        order = { 65, 66, 70 },
    },
    DEMONHUNTER = {
        header = "恶魔猎手设置",
        color = "a330c9",
        mode = "SPEC",
        displayRows = {
            { specIDs = { 577 },  enabledKey = "dh_enable_havoc",     formatKey = "dh_fmt_havoc" },
            { specIDs = { 581 },  enabledKey = "dh_enable_vengeance", formatKey = "dh_fmt_vengeance" },
            { specIDs = { 1480 }, enabledKey = "dh_enable_devourer",  formatKey = "dh_fmt_devourer" },
        },
        specs = {
            [577] = {
                spellID = 195072,
                enabledKey = "dh_enable_havoc",
                formatKey = "dh_fmt_havoc",
                defaultFormat = "没有冲 (%t)",
            },
            [581] = {
                spellID = 189110,
                enabledKey = "dh_enable_vengeance",
                formatKey = "dh_fmt_vengeance",
                defaultFormat = "没有跳 (%t)",
            },
            [1480] = {
                spellID = 1234796,
                enabledKey = "dh_enable_devourer",
                formatKey = "dh_fmt_devourer",
                defaultFormat = "我没有闪 (%t)",
            },
        },
        order = { 577, 581, 1480 },
    },
    EVOKER = {
        header = "唤魔师设置",
        color = "33937f",
        mode = "SPEC",
        displayRows = {
            { specIDs = { 1467 }, enabledKey = "evoker_enable_devastation",  formatKey = "evoker_fmt_devastation" },
            { specIDs = { 1468 }, enabledKey = "evoker_enable_preservation", formatKey = "evoker_fmt_preservation" },
            { specIDs = { 1473 }, enabledKey = "evoker_enable_augmentation", formatKey = "evoker_fmt_augmentation" },
        },
        specs = {
            [1467] = {
                spellID = 358267,
                enabledKey = "evoker_enable_devastation",
                formatKey = "evoker_fmt_devastation",
                defaultFormat = "我没有闪 (%t)",
            },
            [1468] = {
                spellID = 358267,
                enabledKey = "evoker_enable_preservation",
                formatKey = "evoker_fmt_preservation",
                defaultFormat = "我没有闪 (%t)",
            },
            [1473] = {
                spellID = 358267,
                enabledKey = "evoker_enable_augmentation",
                formatKey = "evoker_fmt_augmentation",
                defaultFormat = "我没有闪 (%t)",
            },
        },
        order = { 1467, 1468, 1473 },
    },
}

local CLASS_CONFIG_ORDER = { "MAGE", "DEATHKNIGHT", "ROGUE", "PALADIN", "DEMONHUNTER", "EVOKER" }
local CONFIG_REFRESH_KEYS = {
    enabled = true,
    mage_enable = true,
    dk_enable_steed = true,
    rogue_enable_shadow = true,
    rogue_enable_phantom = true,
    paladin_enable_holy = true,
    paladin_enable_protection = true,
    paladin_enable_retribution = true,
    dh_enable_havoc = true,
    dh_enable_vengeance = true,
    dh_enable_devourer = true,
    evoker_enable_devastation = true,
    evoker_enable_preservation = true,
    evoker_enable_augmentation = true,
}

local function GetSpecInfoForConfig(specID)
    local spec = EXDB and EXDB.SpecByID and EXDB.SpecByID[specID]
    if spec then
        return spec.name or tostring(specID), spec.icon or 136116
    end

    if GetSpecializationInfoForSpecID then
        local name, _, _, icon = GetSpecializationInfoForSpecID(specID)
        return name or tostring(specID), icon or 136116
    end

    return tostring(specID), 136116
end

local function GetIconMarkup(icon, size)
    return string.format("|T%d:%d:%d:0:0:64:64:5:59:5:59|t", tonumber(icon) or 136116, size or 18, size or 18)
end

local function GetDisplayRowLabel(row)
    if row.specIDs then
        local parts = {}
        for _, specID in ipairs(row.specIDs) do
            local specName, specIcon = GetSpecInfoForConfig(specID)
            parts[#parts + 1] = GetIconMarkup(specIcon, 18) .. " " .. L[specName]
        end
        return table.concat(parts, "  ")
    end

    return GetIconMarkup(row.icon or 136116, 18) .. " " .. L[row.label or ""]
end

local function IsConfigRefreshKey(key)
    return key and CONFIG_REFRESH_KEYS[key] == true
end

local function AppendSkillConfigLayout(layout, startY)
    local y = startY

    for _, classTag in ipairs(CLASS_CONFIG_ORDER) do
        local classConfig = NO_MOVE_SKILL_CONFIGS[classTag]
        if classConfig then
            layout[#layout + 1] = {
                key = "h_" .. classTag,
                type = "header",
                x = 1,
                y = y,
                w = 216,
                h = 8,
                label = "|cff" .. classConfig.color .. L[classConfig.header] .. "|r",
                labelSize = 20,
            }
            y = y + 16

            if classConfig.displayRows then
                for _, row in ipairs(classConfig.displayRows) do
                    layout[#layout + 1] = {
                        key = row.enabledKey or ("desc_" .. row.formatKey),
                        type = row.enabledKey and "checkbox" or "description",
                        x = 1,
                        y = y,
                        w = row.enabledKey and 24 or 96,
                        h = 8,
                        label = row.enabledKey and L["启用"] or GetDisplayRowLabel(row),
                    }
                    layout[#layout + 1] = {
                        key = "desc_" .. row.formatKey,
                        type = "description",
                        x = row.enabledKey and 32 or 4,
                        y = y,
                        w = row.enabledKey and 68 or 96,
                        h = 8,
                        label = GetDisplayRowLabel(row),
                    }
                    layout[#layout + 1] = {
                        key = row.formatKey,
                        type = "input",
                        x = 108,
                        y = y,
                        w = 104,
                        h = 8,
                        label = L["显示CD时的内容 (用 %t 代表时间)"],
                        labelPos = "top",
                    }
                    y = y + 16
                end
            elseif classConfig.order then
                local usedFormatKeys = {}
                for _, specID in ipairs(classConfig.order) do
                    local skill = classConfig.specs and classConfig.specs[specID]
                    if skill and not usedFormatKeys[skill.formatKey] then
                        usedFormatKeys[skill.formatKey] = true
                        local specName, specIcon = GetSpecInfoForConfig(specID)
                        layout[#layout + 1] = {
                            key = "desc_" .. skill.formatKey,
                            type = "description",
                            x = 1,
                            y = y,
                            w = 96,
                            h = 8,
                            label = GetIconMarkup(specIcon, 18) .. " " .. L[specName],
                        }
                        layout[#layout + 1] = {
                            key = skill.formatKey,
                            type = "input",
                            x = 108,
                            y = y,
                            w = 104,
                            h = 8,
                            label = L["显示CD时的内容 (用 %t 代表时间)"],
                            labelPos = "top",
                        }
                        y = y + 16
                    end
                end
            end
        end
    end
end

local function EX_RegisterLayout()
    local layout = {
        { key = "header", type = "header", x = 1, y = 1, w = 200, h = 8, label = L["位移技能CD提示"], labelSize = 25 },
        { key = "enabled", type = "checkbox", x = 1, y = 13, w = 40, h = 8, label = L["启用"] },
        { key = "header_skill_content", type = "header", x = 1, y = 105, w = 200, h = 8, label = L["显示内容"], labelSize = 20 },
        { key = "h_MAGE", type = "header", x = 1, y = 115, w = 200, h = 8, label = L["|cff3fc7eb法师设置|r"], labelSize = 20 },
        { key = "mage_enable", type = "checkbox", x = 1, y = 125, w = 24, h = 6, label = L["启用"] },
        { key = "desc_displayFormat", type = "description", x = 31, y = 126, w = 46, h = 6, label = L["|T135932:18:18:0:0:64:64:5:59:5:59|t 奥术  |T135810:18:18:0:0:64:64:5:59:5:59|t 火焰  |T135846:18:18:0:0:64:64:5:59:5:59|t 冰霜"] },
        { key = "displayFormat", type = "input", x = 92, y = 126, w = 46, h = 6, label = L["显示CD时的内容 (用 %t 代表时间)"], labelPos = "top" },
        { key = "h_DEATHKNIGHT", type = "header", x = 1, y = 133, w = 200, h = 8, label = L["|cffc41e3a死亡骑士设置|r"], labelSize = 20 },
        { key = "dk_enable_steed", type = "checkbox", x = 1, y = 143, w = 24, h = 6, label = L["启用"] },
        { key = "desc_dk_fmt_steed", type = "description", x = 31, y = 145, w = 46, h = 6, label = L["|T135770:18:18:0:0:64:64:5:59:5:59|t 鲜血  |T135773:18:18:0:0:64:64:5:59:5:59|t 冰霜  |T135775:18:18:0:0:64:64:5:59:5:59|t 邪恶"] },
        { key = "dk_fmt_steed", type = "input", x = 92, y = 146, w = 46, h = 6, label = L["显示CD时的内容 (用 %t 代表时间)"], labelPos = "top" },
        { key = "h_ROGUE", type = "header", x = 1, y = 153, w = 216, h = 8, label = L["|cfffff468盗贼设置|r"], labelSize = 20 },
        { key = "rogue_enable_shadow", type = "checkbox", x = 1, y = 163, w = 24, h = 6, label = L["启用"] },
        { key = "desc_rogue_fmt_shadow", type = "description", x = 31, y = 163, w = 46, h = 6, label = L["|T236270:18:18:0:0:64:64:5:59:5:59|t 奇袭  |T132320:18:18:0:0:64:64:5:59:5:59|t 敏锐"] },
        { key = "rogue_fmt_shadow", type = "input", x = 92, y = 164, w = 46, h = 6, label = L["显示CD时的内容 (用 %t 代表时间)"], labelPos = "top" },
        { key = "rogue_enable_phantom", type = "checkbox", x = 1, y = 173, w = 24, h = 6, label = L["启用"] },
        { key = "desc_rogue_fmt_phantom", type = "description", x = 31, y = 174, w = 46, h = 6, label = L["|T236286:18:18:0:0:64:64:5:59:5:59|t 狂徒"] },
        { key = "rogue_fmt_phantom", type = "input", x = 92, y = 176, w = 46, h = 6, label = L["显示CD时的内容 (用 %t 代表时间)"], labelPos = "top" },
        { key = "h_PALADIN", type = "header", x = 1, y = 183, w = 216, h = 8, label = L["|cfff48cba圣骑士设置|r"], labelSize = 20 },
        { key = "paladin_enable_holy", type = "checkbox", x = 1, y = 193, w = 24, h = 6, label = L["启用"] },
        { key = "desc_paladin_fmt_holy", type = "description", x = 31, y = 213, w = 46, h = 6, label = L["|T135920:18:18:0:0:64:64:5:59:5:59|t 神圣"] },
        { key = "paladin_fmt_holy", type = "input", x = 92, y = 193, w = 46, h = 6, label = L["显示CD时的内容 (用 %t 代表时间)"], labelPos = "top" },
        { key = "paladin_enable_protection", type = "checkbox", x = 1, y = 203, w = 24, h = 6, label = L["启用"] },
        { key = "desc_paladin_fmt_protection", type = "description", x = 31, y = 193, w = 46, h = 6, label = L["|T236264:18:18:0:0:64:64:5:59:5:59|t 防护"] },
        { key = "paladin_fmt_protection", type = "input", x = 92, y = 203, w = 46, h = 6, label = L["显示CD时的内容 (用 %t 代表时间)"], labelPos = "top" },
        { key = "paladin_enable_retribution", type = "checkbox", x = 1, y = 213, w = 24, h = 6, label = L["启用"] },
        { key = "desc_paladin_fmt_retribution", type = "description", x = 31, y = 203, w = 46, h = 6, label = L["|T135873:18:18:0:0:64:64:5:59:5:59|t 惩戒"] },
        { key = "paladin_fmt_retribution", type = "input", x = 92, y = 213, w = 46, h = 6, label = L["显示CD时的内容 (用 %t 代表时间)"], labelPos = "top" },
        { key = "h_DEMONHUNTER", type = "header", x = 1, y = 224, w = 216, h = 8, label = L["|cffa330c9恶魔猎手设置|r"], labelSize = 20 },
        { key = "dh_enable_havoc", type = "checkbox", x = 1, y = 233, w = 24, h = 6, label = L["启用"] },
        { key = "desc_dh_fmt_havoc", type = "description", x = 31, y = 243, w = 46, h = 6, label = L["|T1247264:18:18:0:0:64:64:5:59:5:59|t 浩劫"] },
        { key = "dh_fmt_havoc", type = "input", x = 92, y = 243, w = 46, h = 6, label = L["显示CD时的内容 (用 %t 代表时间)"], labelPos = "top" },
        { key = "dh_enable_vengeance", type = "checkbox", x = 1, y = 243, w = 24, h = 6, label = L["启用"] },
        { key = "desc_dh_fmt_vengeance", type = "description", x = 31, y = 253, w = 46, h = 6, label = L["|T1247265:18:18:0:0:64:64:5:59:5:59|t 复仇"] },
        { key = "dh_fmt_vengeance", type = "input", x = 92, y = 253, w = 46, h = 6, label = L["显示CD时的内容 (用 %t 代表时间)"], labelPos = "top" },
        { key = "dh_enable_devourer", type = "checkbox", x = 1, y = 253, w = 24, h = 6, label = L["启用"] },
        { key = "desc_dh_fmt_devourer", type = "description", x = 31, y = 233, w = 46, h = 6, label = L["|T7455385:18:18:0:0:64:64:5:59:5:59|t 噬灭"] },
        { key = "dh_fmt_devourer", type = "input", x = 92, y = 233, w = 46, h = 6, label = L["显示CD时的内容 (用 %t 代表时间)"], labelPos = "top" },
        { key = "h_EVOKER", type = "header", x = 1, y = 263, w = 216, h = 8, label = L["|cff33937f唤魔师设置|r"], labelSize = 20 },
        { key = "evoker_enable_devastation", type = "checkbox", x = 1, y = 273, w = 24, h = 6, label = L["启用"] },
        { key = "desc_evoker_fmt_devastation", type = "description", x = 31, y = 273, w = 46, h = 6, label = L["|T4511811:18:18:0:0:64:64:5:59:5:59|t 湮灭"] },
        { key = "evoker_fmt_devastation", type = "input", x = 92, y = 273, w = 46, h = 6, label = L["显示CD时的内容 (用 %t 代表时间)"], labelPos = "top" },
        { key = "evoker_enable_preservation", type = "checkbox", x = 1, y = 283, w = 24, h = 6, label = L["启用"] },
        { key = "desc_evoker_fmt_preservation", type = "description", x = 31, y = 283, w = 46, h = 6, label = L["|T4511812:18:18:0:0:64:64:5:59:5:59|t 恩护"] },
        { key = "evoker_fmt_preservation", type = "input", x = 92, y = 283, w = 46, h = 6, label = L["显示CD时的内容 (用 %t 代表时间)"], labelPos = "top" },
        { key = "evoker_enable_augmentation", type = "checkbox", x = 1, y = 293, w = 24, h = 6, label = L["启用"] },
        { key = "desc_evoker_fmt_augmentation", type = "description", x = 31, y = 293, w = 46, h = 6, label = L["|T5198700:18:18:0:0:64:64:5:59:5:59|t 增辉"] },
        { key = "evoker_fmt_augmentation", type = "input", x = 92, y = 293, w = 46, h = 6, label = L["显示CD时的内容 (用 %t 代表时间)"], labelPos = "top" },
    }

    return layout
end
local GUI_STATIC  = EX_RegisterLayout()

-- =============================================================
-- 默认设置
-- =============================================================
local EX_DEFAULTS = {
    layout                     = { direction = "DOWN", spacing = 0, maxVisible = 1 },
    displayFormat              = "我没有闪 (%t)",
    enabled                    = true,
    mage_enable                = true,
    font_alert                 = {
        a = 1,
        justifyH = "CENTER",
        justifyV = "MIDDLE",
        wordWrap = false,
        b = 1,
        font = "默认",
        g = 1,
        outline = "OUTLINE",
        r = 1,
        shadow = false,
        shadowX = 2,
        shadowY = -2,
        size = 15,
        x = DEFAULT_ALERT_OFFSET_X,
        y = DEFAULT_ALERT_OFFSET_Y,
        attachToCustom = false,
        customAttachTarget = "",
    },
    dk_enable_steed            = true,
    dk_fmt_steed               = "没有骑马 (%t)",
    -- 盗贼专属
    rogue_enable_shadow        = true,
    rogue_enable_phantom       = true,
    rogue_fmt_shadow           = "没有影步 (%t)",
    rogue_fmt_phantom          = "没有爪钩 (%t)",
    paladin_fmt_steed          = "没有骑马 (%t)",
    paladin_enable_holy        = true,
    paladin_enable_protection  = true,
    paladin_enable_retribution = true,
    paladin_fmt_holy           = "没有骑马 (%t)",
    paladin_fmt_protection     = "没有骑马 (%t)",
    paladin_fmt_retribution    = "没有骑马 (%t)",
    dh_enable_havoc            = false,
    dh_enable_vengeance        = false,
    dh_enable_devourer         = true,
    dh_fmt_havoc               = "没有冲 (%t)",
    dh_fmt_vengeance           = "没有跳 (%t)",
    dh_fmt_devourer            = "我没有闪 (%t)",
    evoker_enable_devastation  = true,
    evoker_enable_preservation = true,
    evoker_enable_augmentation = true,
    evoker_fmt_devastation     = "我没有闪 (%t)",
    evoker_fmt_preservation    = "我没有闪 (%t)",
    evoker_fmt_augmentation    = "我没有闪 (%t)",
}

local MODULE_SPEC = {
    RefreshActiveSurfaces = function(controller) return RefreshActiveSurfaces(controller) end,
    moduleKey = MODULE_KEY,
    kind = "text",
    anchor = {
        dbPath = "font_alert",
        xKey = "x",
        yKey = "y",
        defaultX = DEFAULT_ALERT_OFFSET_X,
        defaultY = DEFAULT_ALERT_OFFSET_Y,
        attachEnabledKey = "attachToCustom",
        attachTargetKey = "customAttachTarget",
        initialWidth = 120,
        initialHeight = 32,
        clampedToScreen = true,
        -- GUI 位于 font_alert 作用域；直接绑定该表，不能再创建 font_alert.anchorGroup。
        bindRoot = true,
    },
    preview = {
        positionGuiKeys = {},
        elements = {
            ["nomoveskillalert.body"] = { guiKey = "font_alert", movable = false, tooltip = L["位移技能CD提示"] },
        },
    },
    defaults = { root = EX_DEFAULTS },
    gui = {
        static = GUI_STATIC,
        fields = {
            { key = "font_alert", type = "fontgroup", x = 1, y = 50, w = 200, h = 50, label = L["提示文字"], labelSize = 20 },
            {
                key = "anchorGroup",
                parentKey = "font_alert",
                type = "anchorgroup",
                x = 1,
                y = 30,
                w = 200,
                h = 18,
                measure = true,
                label = L["锚点设置"]
            },
        },
    },
}

ExwindTools:DeclareModuleSpecDefaults(MODULE_KEY, MODULE_SPEC.defaults)
local DB = ExwindTools:GetModuleDB(MODULE_KEY)
local central = EXUI:RegisterTextModule(MODULE_SPEC)
local LAYOUT = DB.layout
if not ExwindTools:IsModuleEnabled(MODULE_KEY) then return end

-- =============================================================
-- [盗贼] 事件驱动引擎
-- 监听 UNIT_SPELLCAST_SUCCEEDED，按专精决定监控法术与计时器时长：
--   259(奇袭)/261(敏锐) → 36554(影步)  30秒
--   260(狂徒)           → 195457(幽灵步) 45秒
-- 冷却文字由原生 DurationTextBinding 渲染；模块仅在事件状态改变时重绑。
-- =============================================================
local rogueSkillConfig      = nil
local mageClassTag          = nil
local mageSpellID           = nil
local paladinSkillConfig    = nil

-- 显示宿主完全属于中央 Text controller。模块只保留业务 payload，并将同一份
-- presentation 提交给 Runtime / World / Panel；font_alert.x/y 是整体 Anchor。
local runtimeText           = ""
local runtimeDuration       = nil
local runtimeDurationFormat = nil
local runtimeVisible        = false
local RUNTIME_ITEM_ID       = "nomoveskillalert:runtime"

local function BodyBounds()
    local size = tonumber((DB.font_alert or {}).size) or 15
    return math.max(120, math.floor(size * 12)), math.max(32, math.floor(size + 20))
end

local function BuildPresentation(text, nativeRemainingDuration, nativeRemainingFormat)
    local width, height = BodyBounds()
    local halfWidth, halfHeight = width * 0.5, height * 0.5
    return {
        text = text or "",
        secretText = type(_G.issecretvalue) == "function" and _G.issecretvalue(text),
        durationObject = nativeRemainingDuration,
        durationOptions = nativeRemainingDuration and {
            property = Enum.DurationTextBindingProperty.RemainingDuration,
            formatString = nativeRemainingFormat,
            -- 原生 DurationTextBinding 的通用默认会在结束时显示 "0"；本模块的
            -- 业务语义是“无可用位移 CD 时隐藏提示”，故零/过期文本必须为空。
            -- 这只配置原生 renderer，不读取或判断 Duration 内部时间。
            expiredText = "",
            zeroDurationText = "",
        } or nil,
        style = DB.font_alert,
        declaredBounds = { left = -halfWidth, right = halfWidth, bottom = -halfHeight, top = halfHeight },
        anchor = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 },
        semanticSlot = "nomoveskillalert.body",
        interaction = EXUI:BuildStandardPreviewInteraction("Text", DB, MODULE_SPEC.preview.elements),
    }
end

local BuildSamplePresentation

local function RefreshRuntimeVisual()
    if runtimeVisible then
        central:SetRuntime({ {
            itemID = RUNTIME_ITEM_ID,
            presentation = BuildPresentation(runtimeText, runtimeDuration, runtimeDurationFormat),
        } }, LAYOUT)
    else
        central:Clear()
    end
end

local function SetRuntimeVisible(visible)
    runtimeVisible = visible == true
    if not runtimeVisible then
        runtimeText = ""
        runtimeDuration = nil
        runtimeDurationFormat = nil
    end
    RefreshRuntimeVisual()
end

-- 正式持续时间文字只持有原生 Duration Object。模块不读取或重算它，
-- TextWidget 的 DurationTextBinding 自行逐帧渲染并在 API 冷却状态变更时重绑。
local function SetAlertDuration(durationObject, formatString)
    runtimeText = ""
    runtimeDuration = durationObject
    runtimeDurationFormat = formatString or "{}"
    RefreshRuntimeVisual()
end

BuildSamplePresentation = function()
    local format = DB.displayFormat or "我没有闪 (%t)"
    -- gsub 会额外返回替换次数；括号强制只把替换后的文本交给中央 presentation，
    -- 绝不能把次数误传为 nativeRemainingDuration。
    return BuildPresentation((format:gsub("%%t", "12")))
end

local function RefreshPreview()
    central:SetPreview({ {
        itemID = "nomoveskillalert:sample",
        presentation = BuildSamplePresentation(),
    } }, LAYOUT)
end

RefreshActiveSurfaces = function(controller)
    if controller.previewEntries and controller.previewEntries[1] then
        controller.previewEntries[1].presentation = BuildSamplePresentation()
    end
    if controller.runtimeEntries and controller.runtimeEntries[1] and runtimeVisible then
        controller.runtimeEntries[1].presentation = BuildPresentation(runtimeText, runtimeDuration, runtimeDurationFormat)
    end
end

RefreshPreview()

local function GetCurrentSpecID()
    local specIndex = GetSpecialization and GetSpecialization()
    if not specIndex then return 0 end
    return GetSpecializationInfo(specIndex) or 0
end

local function ResolveSpecSkillConfig(classTag, specID)
    local classConfig = NO_MOVE_SKILL_CONFIGS[classTag]
    if not classConfig or not classConfig.specs then return nil end
    local skill = classConfig.specs[specID]
    if skill and skill.enabledKey and DB[skill.enabledKey] == false then
        return nil
    end
    return skill
end

local function IsConfiguredSpell(classTag, spellID)
    local classConfig = NO_MOVE_SKILL_CONFIGS[classTag]
    if not classConfig or not classConfig.specs then return false end

    for _, skill in pairs(classConfig.specs) do
        if skill.spellID == spellID then
            return true
        end
    end

    return false
end

-- 盗贼没有 Lua 计时循环：只在目标技能成功施放或配置变更时读取一次 source，
-- 并将 start/duration 原样交给原生 DurationObject。
local function UpdateRogueDirectAlert()
    if not DB.enabled then
        SetRuntimeVisible(false)
        return
    end
    local skill = rogueSkillConfig or ResolveSpecSkillConfig("ROGUE", GetCurrentSpecID())
    if not skill then
        SetRuntimeVisible(false)
        return
    end
    local spellID = skill.spellID
    local info = C_Spell.GetSpellCooldown(spellID)
    if not info or info.isOnGCD ~= false or info.isActive ~= true then
        SetRuntimeVisible(false)
        return
    end
    local fmt = DB[skill.formatKey] or skill.defaultFormat or ""
    local duration = C_Spell.GetSpellCooldownDuration(spellID, true)
    if not duration then
        SetRuntimeVisible(false)
        return
    end
    SetAlertDuration(duration, (fmt:gsub("%%t", "{}")))
    SetRuntimeVisible(true)
end

-- =============================================================
-- [KNOWN_FIRST] 直读 API 引擎
-- 不再手动推算充能/CD，统一通过 C_Spell 读取真实数据
-- =============================================================
local function IsSpellKnownSafe(spellID)
    if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(spellID) then
        return true
    end
    if IsPlayerSpell and IsPlayerSpell(spellID) then
        return true
    end
    return false
end

local function ResolveKnownFirstSkillConfig(classTag)
    local classConfig = NO_MOVE_SKILL_CONFIGS[classTag]
    if not classConfig or not classConfig.candidates then return nil end

    for _, skill in ipairs(classConfig.candidates) do
        if (not skill.enabledKey or DB[skill.enabledKey] ~= false) and IsSpellKnownSafe(skill.spellID) then
            return skill
        end
    end
end

local function HideMageDirectAlert()
    SetRuntimeVisible(false)
end

local function UpdateMageDirectAlert()
    if not DB.enabled or not mageSpellID then
        HideMageDirectAlert()
        return
    end

    local info = C_Spell.GetSpellCooldown(mageSpellID)
    if not info or info.isOnGCD ~= false or info.isActive ~= true then
        HideMageDirectAlert()
        return
    end

    local classConfig = mageClassTag and NO_MOVE_SKILL_CONFIGS[mageClassTag]
    local fallback = classConfig and classConfig.displayRows and classConfig.displayRows[1]
    local fmt
    if mageClassTag == "MAGE" then
        fmt = DB.displayFormat
    elseif mageClassTag == "DEATHKNIGHT" then
        fmt = DB.dk_fmt_steed
    else
        error("NoMoveSkillAlert known-first class has no declared format field: " .. tostring(mageClassTag), 2)
    end
    fmt = fmt or (fallback and fallback.defaultFormat) or "我没有闪 (%t)"
    local duration = C_Spell.GetSpellCooldownDuration(mageSpellID, true)
    if not duration then
        HideMageDirectAlert()
        return
    end
    SetAlertDuration(duration, (fmt:gsub("%%t", "{}")))
    SetRuntimeVisible(true)
end

local function HidePaladinDirectAlert()
    SetRuntimeVisible(false)
end

local function UpdatePaladinDirectAlert()
    if not DB.enabled or not paladinSkillConfig then
        HidePaladinDirectAlert()
        return
    end

    local info = C_Spell.GetSpellCooldown(paladinSkillConfig.spellID)
    if not info or info.isOnGCD ~= false or info.isActive ~= true then
        HidePaladinDirectAlert()
        return
    end

    local fmt = DB[paladinSkillConfig.formatKey]
        or (paladinSkillConfig.fallbackFormatKey and DB[paladinSkillConfig.fallbackFormatKey])
        or paladinSkillConfig.defaultFormat
        or "我没有马 (%t)"
    -- 原生 Duration Object 可携带 Secret 值；只原样绑定，不读取其内部时间。
    local duration = C_Spell.GetSpellCooldownDuration(paladinSkillConfig.spellID, true)
    if not duration then
        HidePaladinDirectAlert()
        return
    end
    SetAlertDuration(duration, (fmt:gsub("%%t", "{}")))
    SetRuntimeVisible(true)
end

-- =============================================================
-- 天赋扫描
-- =============================================================
local function RefreshActiveSkillData()
    local _, className = UnitClass("player")

    -- 盗贼只在冷却状态事件时重绑原生 Duration，不创建模块计时循环。
    if className == "ROGUE" then
        mageClassTag = nil
        mageSpellID = nil
        paladinSkillConfig = nil
        if DB.enabled then
            rogueSkillConfig = ResolveSpecSkillConfig("ROGUE", GetCurrentSpecID())
            UpdateRogueDirectAlert()
        else
            rogueSkillConfig = nil
            SetRuntimeVisible(false)
        end
        return
    end

    if className == "MAGE" or className == "DEATHKNIGHT" then
        rogueSkillConfig = nil
        paladinSkillConfig = nil
        mageClassTag = className
        local mageSkill = ResolveKnownFirstSkillConfig(className)
        mageSpellID = mageSkill and mageSkill.spellID or nil
        if DB.enabled and mageSpellID then
            UpdateMageDirectAlert()
        else
            SetRuntimeVisible(false)
        end
        return
    end

    if className == "PALADIN" or className == "DEMONHUNTER" or className == "EVOKER" then
        rogueSkillConfig = nil
        mageClassTag = nil
        mageSpellID = nil
        paladinSkillConfig = ResolveSpecSkillConfig(className, GetCurrentSpecID())
        if DB.enabled and paladinSkillConfig then
            UpdatePaladinDirectAlert()
        else
            paladinSkillConfig = nil
            SetRuntimeVisible(false)
        end
        return
    end

    rogueSkillConfig = nil
    mageClassTag = nil
    mageSpellID = nil
    paladinSkillConfig = nil
    SetRuntimeVisible(false)
end



-- =============================================================
-- 事件注册
-- =============================================================
ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", MODULE_KEY, function()
    C_Timer.After(1, RefreshActiveSkillData)
end)

ExwindTools:RegisterEvent("PLAYER_TALENT_UPDATE", MODULE_KEY, function()
    C_Timer.After(0.5, RefreshActiveSkillData)
end)

ExwindTools:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", MODULE_KEY, function(_, unit)
    if unit == "player" then
        C_Timer.After(0.5, RefreshActiveSkillData)
    end
end)

ExwindTools:RegisterEvent("TRAIT_CONFIG_UPDATED", MODULE_KEY, function()
    C_Timer.After(0.5, RefreshActiveSkillData)
end)

ExwindTools:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", MODULE_KEY, function(_, _, _, spellID)
    -- 冷却 API 在该单位事件之后才写入新状态；短暂延后读取这一次
    -- 施法的冷却，且不会回到全局 SPELL_UPDATE_COOLDOWN 广播。
    C_Timer.After(0.1, function()
        if not DB.enabled then return end

        if rogueSkillConfig then
            if not IsConfiguredSpell("ROGUE", spellID) then return end
            rogueSkillConfig = ResolveSpecSkillConfig("ROGUE", GetCurrentSpecID())
            if rogueSkillConfig and rogueSkillConfig.spellID == spellID then
                UpdateRogueDirectAlert()
            end
        elseif mageSpellID == spellID then
            UpdateMageDirectAlert()
        elseif paladinSkillConfig and paladinSkillConfig.spellID == spellID then
            UpdatePaladinDirectAlert()
        end
    end)
end)


ExwindTools:ReportReady(MODULE_KEY)
