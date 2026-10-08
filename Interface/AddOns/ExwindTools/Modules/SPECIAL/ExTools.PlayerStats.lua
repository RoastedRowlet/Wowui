-- [[ 玩家属性面板 ]]
-- { Key = "ExTools.PlayerStats", Name = "玩家属性面板", Desc = "在屏幕上显示高度自定义的玩家属性（急速、全能、躲闪等）。", Category = 4 },

-- =========================================================
-- 一、模块标识与依赖引用 | Module Identity and Dependencies
-- =========================================================
local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXState = ExwindTools.State
local L = (ExwindTools and ExwindTools.L) or setmetatable({}, { __index = function(_, key) return key end })

local EXWIND_MODULE_KEY = "ExTools.PlayerStats"

if not ExwindTools:IsModuleEnabled(EXWIND_MODULE_KEY) then return end

local EXDB = _G.EXDB
local LSM = LibStub("LibSharedMedia-3.0")

local function IsSecretValue(value)
    return type(issecretvalue) == "function" and issecretvalue(value)
end

-- 3. 数据初始化
local function GetDefaultFont()
    return { font = nil, size = 14, outline = "OUTLINE", r = 1, g = 1, b = 1, a = 1, shadow = true, x = 0, y = 0 }
end

local function GetDefaultRows()
    local rows = {}
    local defaultStats = { "主属性", "暴击", "急速", "精通", "全能", "移速" }
    for i = 1, 10 do
        table.insert(rows, {
            enabled = i <= 6,
            label = defaultStats[i] or ("属性" .. i),
            key = defaultStats[i] or "无",
            isPercent = true,
            format = 1,
            syncFont = true,
            roles = { TANK = true, HEALER = true, DAMAGER = true },
            scenes = { ["副本内"] = true, ["副本外"] = true },
            fontLabel = GetDefaultFont(),
            fontValue = GetDefaultFont()
        })
    end
    return rows
end

local function NormalizeDecimalPlaces(value)
    local decimals = tonumber(value)
    if not decimals or decimals ~= decimals or decimals == math.huge or decimals == -math.huge then
        decimals = 1
    end
    decimals = math.floor(decimals)
    if decimals < 0 then
        decimals = 0
    elseif decimals > 3 then
        decimals = 3
    end
    return decimals
end

local STAT_VALUE_FORMATS = {
    [0] = "%.0f",
    [1] = "%.1f",
    [2] = "%.2f",
    [3] = "%.3f",
}

local STAT_PERCENT_FORMATS = {
    [0] = "%.0f%%",
    [1] = "%.1f%%",
    [2] = "%.2f%%",
    [3] = "%.3f%%",
}

-- =========================================================
-- 二、默认配置与配置访问 | Defaults and Configuration Access
-- =========================================================
local EX_DEFAULTS = {
    root = {
        bgSettings = {
            bgColorA = 1,
            bgColorB = 1,
            bgColorG = 1,
            bgColorR = 1,
            borderColorA = 1,
            borderColorB = 1,
            borderColorG = 1,
            borderColorR = 1,
            borderTexture = "EX_WhiteBorder",
            edgeSize = 9,
            inset = 8,
            labelAlign = "RIGHT",
            labelX = 100,
            rowSpacing = 5,
            texture = "EX_WhiteBackground",
            valueAlign = "LEFT",
            valueX = -58,
        },
        pos = {
            attachToCustom = false,
            customAttachTarget = "",
            point = "BOTTOMLEFT",
            x = 426,
            y = 0,
        },
        rows = {
            {
                enabled = true,
                fontLabel = {
                    a = 1,
                    autoWidth = false,
                    b = 0,
                    enabled = true,
                    fixedWidth = 200,
                    font = "默认",
                    g = 0.63137257099152,
                    gradientEnabled = false,
                    gradientLength = 0,
                    gradientStart = 0,
                    justifyH = "LEFT",
                    justifyV = "MIDDLE",
                    maxWidth = 0,
                    outline = "OUTLINE",
                    r = 1,
                    rotation = 0,
                    shadow = false,
                    shadowColorA = 1,
                    shadowColorB = 0,
                    shadowColorG = 0,
                    shadowColorR = 0,
                    shadowX = 1.2000007629395,
                    shadowY = -1,
                    size = 18,
                    x = -1,
                    y = 2,
                },
                fontValue = {
                    a = 1,
                    autoWidth = false,
                    b = 1,
                    enabled = true,
                    fixedWidth = 200,
                    font = "默认",
                    g = 1,
                    gradientEnabled = false,
                    gradientLength = 0,
                    gradientStart = 0,
                    justifyH = "LEFT",
                    justifyV = "MIDDLE",
                    maxWidth = 0,
                    outline = "OUTLINE",
                    r = 1,
                    rotation = 0,
                    shadow = true,
                    shadowColorA = 1,
                    shadowColorB = 0,
                    shadowColorG = 0,
                    shadowColorR = 0,
                    shadowX = 1,
                    shadowY = -1,
                    size = 14,
                    x = 0,
                    y = 0,
                },
                format = 0,
                isPercent = false,
                key = "主属性",
                label = "%主属性",
                roles = {
                    DAMAGER = true,
                    HEALER = true,
                    TANK = true,
                },
                scenes = {
                    ["副本内"] = true,
                    ["副本外"] = true,
                },
                syncFont = true,
            },
            {
                enabled = true,
                fontLabel = {
                    a = 1,
                    autoWidth = false,
                    b = 0.32549020648003,
                    enabled = true,
                    fixedWidth = 200,
                    font = "默认",
                    g = 0.23921570181847,
                    gradientEnabled = false,
                    gradientLength = 0,
                    gradientStart = 0,
                    justifyH = "LEFT",
                    justifyV = "MIDDLE",
                    maxWidth = 0,
                    outline = "OUTLINE",
                    r = 1,
                    rotation = 0,
                    shadow = false,
                    shadowColorA = 1,
                    shadowColorB = 0,
                    shadowColorG = 0,
                    shadowColorR = 0,
                    shadowX = 1,
                    shadowY = -1,
                    size = 18,
                    x = 0,
                    y = 0,
                },
                fontValue = {
                    a = 1,
                    autoWidth = false,
                    b = 1,
                    enabled = true,
                    fixedWidth = 200,
                    font = "默认",
                    g = 1,
                    gradientEnabled = false,
                    gradientLength = 0,
                    gradientStart = 0,
                    justifyH = "LEFT",
                    justifyV = "MIDDLE",
                    maxWidth = 0,
                    outline = "OUTLINE",
                    r = 1,
                    rotation = 0,
                    shadow = true,
                    shadowColorA = 1,
                    shadowColorB = 0,
                    shadowColorG = 0,
                    shadowColorR = 0,
                    shadowX = 1,
                    shadowY = -1,
                    size = 14,
                    x = 0,
                    y = 0,
                },
                format = 1,
                isPercent = true,
                key = "暴击",
                label = "暴击",
                roles = {
                    DAMAGER = true,
                    HEALER = true,
                    TANK = true,
                },
                scenes = {
                    ["副本内"] = true,
                    ["副本外"] = true,
                },
                syncFont = true,
            },
            {
                enabled = true,
                fontLabel = {
                    a = 1,
                    autoWidth = false,
                    b = 0.0078431377187371,
                    enabled = true,
                    fixedWidth = 200,
                    font = "默认",
                    g = 1,
                    gradientEnabled = false,
                    gradientLength = 0,
                    gradientStart = 0,
                    justifyH = "LEFT",
                    justifyV = "MIDDLE",
                    maxWidth = 0,
                    outline = "OUTLINE",
                    r = 0.52156865596771,
                    rotation = 0,
                    shadow = false,
                    shadowColorA = 1,
                    shadowColorB = 0,
                    shadowColorG = 0,
                    shadowColorR = 0,
                    shadowX = 1,
                    shadowY = -1,
                    size = 18,
                    x = 0,
                    y = 0,
                },
                fontValue = {
                    a = 1,
                    autoWidth = false,
                    b = 1,
                    enabled = true,
                    fixedWidth = 200,
                    font = "默认",
                    g = 1,
                    gradientEnabled = false,
                    gradientLength = 0,
                    gradientStart = 0,
                    justifyH = "LEFT",
                    justifyV = "MIDDLE",
                    maxWidth = 0,
                    outline = "THICKOUTLINE",
                    r = 1,
                    rotation = 0,
                    shadow = false,
                    shadowColorA = 1,
                    shadowColorB = 0,
                    shadowColorG = 0,
                    shadowColorR = 0,
                    shadowX = 1,
                    shadowY = -1,
                    size = 14,
                    x = 0,
                    y = 0,
                },
                format = 1,
                isPercent = true,
                key = "急速",
                label = "急速",
                roles = {
                    DAMAGER = true,
                    HEALER = true,
                    TANK = true,
                },
                scenes = {
                    ["副本内"] = true,
                    ["副本外"] = true,
                },
                syncFont = true,
            },
            {
                enabled = true,
                fontLabel = {
                    a = 1,
                    autoWidth = false,
                    b = 1,
                    enabled = true,
                    fixedWidth = 200,
                    font = "默认",
                    g = 0.57254904508591,
                    gradientEnabled = false,
                    gradientLength = 0,
                    gradientStart = 0,
                    justifyH = "LEFT",
                    justifyV = "MIDDLE",
                    maxWidth = 0,
                    outline = "OUTLINE",
                    r = 0.04313725605607,
                    rotation = 0,
                    shadow = false,
                    shadowColorA = 1,
                    shadowColorB = 0,
                    shadowColorG = 0,
                    shadowColorR = 0,
                    shadowX = 1,
                    shadowY = -1,
                    size = 18,
                    x = 0,
                    y = 0,
                },
                fontValue = {
                    a = 1,
                    autoWidth = false,
                    b = 1,
                    enabled = true,
                    fixedWidth = 200,
                    font = "默认",
                    g = 1,
                    gradientEnabled = false,
                    gradientLength = 0,
                    gradientStart = 0,
                    justifyH = "LEFT",
                    justifyV = "MIDDLE",
                    maxWidth = 0,
                    outline = "OUTLINE",
                    r = 1,
                    rotation = 0,
                    shadow = true,
                    shadowColorA = 1,
                    shadowColorB = 0,
                    shadowColorG = 0,
                    shadowColorR = 0,
                    shadowX = 1,
                    shadowY = -1,
                    size = 15,
                    x = 0,
                    y = 0,
                },
                format = 1,
                isPercent = true,
                key = "精通",
                label = "精通",
                roles = {
                    DAMAGER = true,
                    HEALER = true,
                    TANK = true,
                },
                scenes = {
                    ["副本内"] = true,
                    ["副本外"] = true,
                },
                syncFont = true,
            },
            {
                enabled = true,
                fontLabel = {
                    a = 1,
                    autoWidth = false,
                    b = 1,
                    enabled = true,
                    fixedWidth = 200,
                    font = "默认",
                    g = 0.90980398654938,
                    gradientEnabled = false,
                    gradientLength = 0,
                    gradientStart = 0,
                    justifyH = "LEFT",
                    justifyV = "MIDDLE",
                    maxWidth = 0,
                    outline = "OUTLINE",
                    r = 0.3647058904171,
                    rotation = 0,
                    shadow = false,
                    shadowColorA = 1,
                    shadowColorB = 0,
                    shadowColorG = 0,
                    shadowColorR = 0,
                    shadowX = 1,
                    shadowY = -1,
                    size = 18,
                    x = 0,
                    y = 0,
                },
                fontValue = {
                    a = 1,
                    autoWidth = false,
                    b = 1,
                    enabled = true,
                    fixedWidth = 200,
                    font = "默认",
                    g = 1,
                    gradientEnabled = false,
                    gradientLength = 0,
                    gradientStart = 0,
                    justifyH = "LEFT",
                    justifyV = "MIDDLE",
                    maxWidth = 0,
                    outline = "OUTLINE",
                    r = 1,
                    rotation = 0,
                    shadow = false,
                    shadowColorA = 1,
                    shadowColorB = 0,
                    shadowColorG = 0,
                    shadowColorR = 0,
                    shadowX = 1,
                    shadowY = -1,
                    size = 14,
                    x = 0,
                    y = 0,
                },
                format = 1,
                isPercent = true,
                key = "全能",
                label = "全能",
                roles = {
                    DAMAGER = true,
                    HEALER = true,
                    TANK = true,
                },
                scenes = {
                    ["副本内"] = true,
                    ["副本外"] = true,
                },
                syncFont = true,
            },
            {
                enabled = true,
                fontLabel = {
                    a = 1,
                    autoWidth = false,
                    b = 0.28627452254295,
                    enabled = true,
                    fixedWidth = 200,
                    font = "默认",
                    g = 0.91372555494308,
                    gradientEnabled = false,
                    gradientLength = 0,
                    gradientStart = 0,
                    justifyH = "LEFT",
                    justifyV = "MIDDLE",
                    maxWidth = 0,
                    outline = "OUTLINE",
                    r = 1,
                    rotation = 0,
                    shadow = false,
                    shadowColorA = 1,
                    shadowColorB = 0,
                    shadowColorG = 0,
                    shadowColorR = 0,
                    shadowX = 1,
                    shadowY = -1,
                    size = 18,
                    x = 0,
                    y = 0,
                },
                fontValue = {
                    a = 1,
                    autoWidth = false,
                    b = 1,
                    enabled = true,
                    fixedWidth = 200,
                    font = "默认",
                    g = 1,
                    gradientEnabled = false,
                    gradientLength = 0,
                    gradientStart = 0,
                    justifyH = "LEFT",
                    justifyV = "MIDDLE",
                    maxWidth = 0,
                    outline = "OUTLINE",
                    r = 1,
                    rotation = 0,
                    shadow = true,
                    shadowColorA = 1,
                    shadowColorB = 0,
                    shadowColorG = 0,
                    shadowColorR = 0,
                    shadowX = 1,
                    shadowY = -1,
                    size = 14,
                    x = 0,
                    y = 0,
                },
                format = 0,
                isPercent = true,
                key = "移速",
                label = "移速",
                roles = {
                    DAMAGER = true,
                    HEALER = true,
                    TANK = true,
                },
                scenes = {
                    ["副本内"] = true,
                    ["副本外"] = true,
                },
                syncFont = true,
            },
            {
                enabled = true,
                fontLabel = {
                    a = 1,
                    autoWidth = false,
                    b = 1,
                    enabled = true,
                    fixedWidth = 200,
                    font = "默认",
                    g = 1,
                    gradientEnabled = false,
                    gradientLength = 0,
                    gradientStart = 0,
                    justifyH = "LEFT",
                    justifyV = "MIDDLE",
                    maxWidth = 0,
                    outline = "OUTLINE",
                    r = 1,
                    rotation = 0,
                    shadow = true,
                    shadowColorA = 1,
                    shadowColorB = 0,
                    shadowColorG = 0,
                    shadowColorR = 0,
                    shadowX = 1,
                    shadowY = -1,
                    size = 18,
                    x = 0,
                    y = 0,
                },
                fontValue = {
                    a = 1,
                    autoWidth = false,
                    b = 1,
                    enabled = true,
                    fixedWidth = 200,
                    font = "默认",
                    g = 1,
                    gradientEnabled = false,
                    gradientLength = 0,
                    gradientStart = 0,
                    justifyH = "LEFT",
                    justifyV = "MIDDLE",
                    maxWidth = 0,
                    outline = "OUTLINE",
                    r = 1,
                    rotation = 0,
                    shadow = true,
                    shadowColorA = 1,
                    shadowColorB = 0,
                    shadowColorG = 0,
                    shadowColorR = 0,
                    shadowX = 1,
                    shadowY = -1,
                    size = 14,
                    x = 0,
                    y = 0,
                },
                format = 1,
                isPercent = false,
                key = "装等",
                label = "装等",
                roles = {
                    DAMAGER = true,
                    HEALER = true,
                    TANK = true,
                },
                scenes = {
                    ["副本内"] = true,
                    ["副本外"] = true,
                },
                syncFont = true,
            },
        },
        selectedRow = 5,
        showBg = false,
        showBorder = false,
    },
}

local EX_DEFAULT_SCHEMA = {
    { group = "root", root = true, fields = { "bgSettings", "pos", "rows", "selectedRow", "showBg", "showBorder" } },
}

ExwindTools:DeclareModuleDefaults(EXWIND_MODULE_KEY, EX_DEFAULTS, EX_DEFAULT_SCHEMA)
local EX_DB = ExwindTools:GetModuleDB(EXWIND_MODULE_KEY)
if not EX_DB.rows or #EX_DB.rows == 0 then
    EX_DB.rows = GetDefaultRows()
end
local EXUI = ExwindTools.UI
local GM = ExwindTools.GUIMetrics

local ApplyPlayerStatsLiveVisual
local anchorController, anchorFrame
local EnsureAnchor


local function PickPlayerStatsAnchor()
    if not anchorController and EnsureAnchor then
        EnsureAnchor()
    end
    if anchorController and type(anchorController.StartFramePicker) == "function" then
        return anchorController:StartFramePicker()
    end
    return false
end

local PLAYER_STATS_ANCHOR_OPTS = {
    offsetXKey = "x",
    offsetYKey = "y",
    defaultOffsetX = EX_DEFAULTS.root.pos.x,
    defaultOffsetY = EX_DEFAULTS.root.pos.y,
    attachEnabledKey = "attachToCustom",
    attachTargetKey = "customAttachTarget",
    onPickFrame = PickPlayerStatsAnchor,
}

-- =========================================================
-- 五、业务状态与功能逻辑 | Business State and Logic
-- =========================================================
local STAT_MAP = {
    ["无"] = "None",
    ["主属性"] = "PStat_Major",
    ["力量"] = "PStat_Str",
    ["敏捷"] = "PStat_Agi",
    ["智力"] = "PStat_Int",
    ["暴击"] = "PStat_Crit",
    ["急速"] = "PStat_Haste",
    ["精通"] = "PStat_Mastery",
    ["全能"] = "PStat_VersaText",
    ["吸血"] = "PStat_Leech",
    ["闪避"] = "PStat_Avoidance",
    ["移速"] = "PStat_MovementText",
    ["护甲"] = "PStat_Armor",
    ["躲闪"] = "PStat_Dodge",
    ["招架"] = "PStat_Parry",
    ["格挡"] = "PStat_Block",
    ["装等"] = "PStat_EquippedItemLevel",
    ["血量"] = "PStat_MaxHealth",
    ["耐久"] = "PStat_Durability"
}

ExwindTools.GetRowItems_PlayerStats = function()
    local items = {}
    for i, row in ipairs(EX_DB.rows) do
        local name = (row.label and row.label ~= "") and (L[row.label] or row.label) or (L["属性行 "] .. i)
        table.insert(items, { i .. ": " .. name, i })
    end
    return items
end

ExwindTools.GetPlayerStatTree = function()
    return {
        { L["无"], "无" },
        {
            text = L["主属性"],
            isMenu = true,
            menu = {
                { L["主属性(自动)"], "主属性" }, { L["力量"], "力量" }, { L["敏捷"], "敏捷" }, { L["智力"], "智力" }
            }
        },
        {
            text = L["次要属性"],
            isMenu = true,
            menu = {
                { "|cffFF3D53" .. L["暴击"] .. "|r", "暴击" }, { "|cff85FF02" .. L["急速"] .. "|r", "急速" }, { "|cff0B92FF" .. L["精通"] .. "|r", "精通" }, { "|cff5DE8FF" .. L["全能"] .. "|r", "全能" }
            }
        },
        {
            text = L["第三属性"],
            isMenu = true,
            menu = {
                { L["吸血"], "吸血" }, { L["闪避"], "闪避" }, { L["移速"], "移速" }
            }
        },
        {
            text = L["防御属性"],
            isMenu = true,
            menu = {
                { L["护甲"], "护甲" }, { L["躲闪"], "躲闪" }, { L["招架"], "招架" }, { L["格挡"], "格挡" }
            }
        },
        {
            text = L["其他"],
            isMenu = true,
            menu = {
                { L["装等"], "装等" }, { L["血量"], "血量" }, { L["耐久"], "耐久" }
            }
        }
    }
end

-- =========================================================
-- 三、GUI 声明 | GUI Declarations — Settings Table Renderer / 设置表格渲染器
-- =========================================================
local PLAYER_STATS_ROWS_TABLE = "playerstats_rows_table"
local PLAYER_STATS_ROW_ACTIONS = "PlayerStatsRowActions"
local playerStatsFactory = _G.ExwindFactory
if not playerStatsFactory then error("PlayerStats requires ExwindFactory", 2) end
if not playerStatsFactory.Pools[PLAYER_STATS_ROW_ACTIONS] then
    playerStatsFactory:InitCompositePool(PLAYER_STATS_ROW_ACTIONS)
end

local function ReleasePlayerStatsTableControl(control)
    if not control then return end
    if EXUI.RestoreSettingsListControl then EXUI:RestoreSettingsListControl(control) end
    local factory = _G.ExwindFactory
    if factory and control._isCompositeHost then
        factory:ReleaseCompositeHost(control)
    elseif factory then
        factory:ReleaseGridWidget(control)
    else
        control:Hide()
        control:SetParent(nil)
    end
end

local function ClearPlayerStatsTableRows(controls)
    for index = #controls.rows, 1, -1 do
        local record = controls.rows[index]
        if record.actions then
            record.actions:SetScript("OnSizeChanged", nil)
            for _, button in ipairs(record.actionButtons or {}) do
                ReleasePlayerStatsTableControl(button)
            end
            ReleasePlayerStatsTableControl(record.actions)
        end
        ReleasePlayerStatsTableControl(record.percent)
        ReleasePlayerStatsTableControl(record.syncFont)
        ReleasePlayerStatsTableControl(record.stat)
        ReleasePlayerStatsTableControl(record.name)
        ReleasePlayerStatsTableControl(record.enabled)
        ReleasePlayerStatsTableControl(record.add)
        controls.rows[index] = nil
    end
end

local function CommitPlayerStatsRowValue(rowIndex, field, value)
    local row = EX_DB.rows[rowIndex]
    if type(row) ~= "table" or row[field] == value then return false end
    return EXUI:CommitModuleValue({
        moduleKey = EXWIND_MODULE_KEY,
        path = ("rows.%d.%s"):format(rowIndex, field),
        readValue = function() return row[field] end,
        writeValue = function(nextValue)
            if EX_DB.rows[rowIndex] == row then row[field] = nextValue end
        end,
    }, value)
end

local function SelectPlayerStatsRow(rowIndex)
    if EX_DB.rows[rowIndex] == nil or EX_DB.selectedRow == rowIndex then return end
    EXUI:CommitModuleValue({
        moduleKey = EXWIND_MODULE_KEY,
        path = "selectedRow",
        readValue = function() return EX_DB.selectedRow end,
        writeValue = function(nextValue) EX_DB.selectedRow = nextValue end,
    }, rowIndex)
end

local function ClickPlayerStatsRowAction(rowIndex, key)
    if not EX_DB.rows[rowIndex] then return end
    SelectPlayerStatsRow(rowIndex)
    ExwindTools:UpdateState(EXWIND_MODULE_KEY .. ".ButtonClicked", {
        key = key,
        ts = GetTime(),
    })
end

local function CreatePlayerStatsRowActions(host, rowIndex, rowCount)
    local actions = playerStatsFactory:AcquireCompositeHost(PLAYER_STATS_ROW_ACTIONS, host)
    actions:SetSize(1, GM.size.buttonHeight * 2 + 4)
    actions:EnableMouse(false)
    local buttons = {
        EXUI:CreateButton(actions, GM.size.buttonHeight, GM.size.buttonHeight, L["选择"], function()
            SelectPlayerStatsRow(rowIndex)
        end, { variant = "secondary", compact = true }),
        EXUI:CreateButton(actions, GM.size.buttonHeight, GM.size.buttonHeight, L["↑"], function()
            ClickPlayerStatsRowAction(rowIndex, "btn_up")
        end, { variant = "secondary", compact = true }),
        EXUI:CreateButton(actions, GM.size.buttonHeight, GM.size.buttonHeight, L["↓"], function()
            ClickPlayerStatsRowAction(rowIndex, "btn_down")
        end, { variant = "secondary", compact = true }),
        EXUI:CreateButton(actions, GM.size.buttonHeight, GM.size.buttonHeight, L["删除"], function()
            ClickPlayerStatsRowAction(rowIndex, "btn_delete")
        end, { variant = "danger", compact = true }),
    }
    if rowIndex == 1 then buttons[2]:Disable() end
    if rowIndex == rowCount then buttons[3]:Disable() end
    if rowCount == 1 then buttons[4]:Disable() end
    local function LayoutActions(_, width)
        local gap = 4
        local buttonWidth = math.max(24, (width - gap) / 2)
        for index, button in ipairs(buttons) do
            local position = ({ 1, 3, 4, 2 })[index]
            button:SetWidth(buttonWidth)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", actions, "TOPLEFT",
                ((position - 1) % 2) * (buttonWidth + gap), -math.floor((position - 1) / 2) * (GM.size.buttonHeight + gap))
        end
    end
    actions:SetScript("OnSizeChanged", LayoutActions)
    LayoutActions(actions, actions:GetWidth())
    return actions, buttons
end

local RebuildPlayerStatsRowsTable

RebuildPlayerStatsRowsTable = function(host, context)
    local controls = host and host._exPlayerStatsRowsTable
    if not controls then return end
    context:ReleaseTablePresentation()
    ClearPlayerStatsTableRows(controls)

    local presentedRecords = {}
    for index, row in ipairs(EX_DB.rows) do
        local rowIndex = index
        local record = {
            enabled = EXUI:CreateCheckbox(host, "", row.enabled == true, function(checked)
                CommitPlayerStatsRowValue(rowIndex, "enabled", checked == true)
            end),
            name = EXUI:CreateEditBox(host, tostring(row.label or ""), 1, GM.size.inputHeight, nil, {
                onEditFocusLost = function(text)
                    CommitPlayerStatsRowValue(rowIndex, "label", text or "")
                end,
            }),
            stat = EXUI:CreateDropdown(host, 1, nil, ExwindTools.GetPlayerStatTree(), row.key, function(value)
                CommitPlayerStatsRowValue(rowIndex, "key", value)
            end),
            syncFont = EXUI:CreateCheckbox(host, L["数值字体跟随名称"], row.syncFont == true, function(checked)
                CommitPlayerStatsRowValue(rowIndex, "syncFont", checked == true)
            end),
            percent = EXUI:CreateCheckbox(host, L["百分比"], row.isPercent == true, function(checked)
                CommitPlayerStatsRowValue(rowIndex, "isPercent", checked == true)
            end),
        }
        record.actions, record.actionButtons = CreatePlayerStatsRowActions(host, rowIndex, #EX_DB.rows)
        controls.rows[#controls.rows + 1] = record
        presentedRecords[#presentedRecords + 1] = {
            cells = {
                { widget = record.enabled, type = "switch" },
                { widget = record.name, type = "input" },
                { widget = record.stat, type = "select" },
                { widget = record.syncFont, type = "switch" },
                { widget = record.percent, type = "switch" },
                { widget = record.actions, type = "actions" },
            },
        }
    end

    local add = EXUI:CreateButton(host, 1, GM.size.buttonHeight, L["新增"], function()
        ExwindTools:UpdateState(EXWIND_MODULE_KEY .. ".ButtonClicked", {
            key = "btn_add",
            ts = GetTime(),
        })
    end, { variant = "primary", compact = true })
    controls.rows[#controls.rows + 1] = { add = add }
    context:SetTableControls({
        add = {
            cells = {
                { text = "" },
                { text = "" },
                { text = "" },
                { text = "" },
                { text = "" },
                { widget = add, type = "button" },
            },
        },
        records = presentedRecords,
    })
end

local playerStatsGrid = ExwindTools.Grid
if not playerStatsGrid then error("PlayerStats requires ExwindGrid", 2) end
playerStatsGrid:RegisterTableControls(PLAYER_STATS_ROWS_TABLE, {
    mount = function(host, context)
        host._exPlayerStatsRowsTable = { rows = {} }
        RebuildPlayerStatsRowsTable(host, context)
    end,
    update = function(host, context)
        RebuildPlayerStatsRowsTable(host, context)
    end,
    release = function(host)
        local controls = host._exPlayerStatsRowsTable
        if controls then ClearPlayerStatsTableRows(controls) end
        host._exPlayerStatsRowsTable = nil
    end,
})

-- =========================================================
-- 三、GUI 声明 | GUI Declarations
-- =========================================================
local function EX_RegisterLayout()
    local sel = tonumber(EX_DB.selectedRow) or 1
    if sel < 1 then sel = 1 end
    if sel > #EX_DB.rows then sel = #EX_DB.rows end

    local currentRowPath = "rows." .. sel
    local currentRow = EX_DB.rows[sel]
    local currentRowName = currentRow and currentRow.label
    if type(currentRowName) ~= "string" or currentRowName == "" then
        currentRowName = L["属性行 "] .. sel
    else
        currentRowName = L[currentRowName] or currentRowName
    end
    local function ApplyLivePreview(value, context)
        if ApplyPlayerStatsLiveVisual then
            ApplyPlayerStatsLiveVisual(value, context)
        end
    end
    local fontLivePreview = {
        size = ApplyLivePreview,
        x = ApplyLivePreview,
        y = ApplyLivePreview,
    }
    -- [普通 sections 迁移边界：设置页] 只迁移纯呈现分区；动态行路径与字体组继续引用同一原数据。
    -- rows.N 动态 path、行增删/排序、属性/职责/场景顺序与 TextList 刷新回调禁止修改；header/subheader 不等于卡片容器。
    local layout = {
        version = 1,
        sections = {
            {
                kind = "settings", id = "common", title = L["通用设置"],
                items = {
                    { key = "showBg", type = "switch", label = L["显示背景"] },
                    { key = "showBorder", type = "switch", label = L["显示边框"] },
                    { key = "texture", type = "select", media = "background", parentKey = "bgSettings", label = L["背景材质"] },
                    { key = "bgColor", type = "color", parentKey = "bgSettings", label = L["背景颜色"] },
                    { key = "borderTexture", type = "select", media = "border", parentKey = "bgSettings", label = L["边框材质"] },
                    { key = "borderColor", type = "color", parentKey = "bgSettings", label = L["边框颜色"] },
                    { key = "edgeSize", type = "slider", parentKey = "bgSettings", label = L["边框粗细"], min = 1, max = 32 },
                    { key = "inset", type = "slider", parentKey = "bgSettings", label = L["边框内距"], min = 0, max = 16 },
                    { key = "labelAlign", type = "select", parentKey = "bgSettings", label = L["标签对齐"], options = {
                        { value = "LEFT", label = L["左对齐"] }, { value = "CENTER", label = L["居中"] }, { value = "RIGHT", label = L["右对齐"] },
                    } },
                    { key = "valueAlign", type = "select", parentKey = "bgSettings", label = L["数值对齐"], options = {
                        { value = "LEFT", label = L["左对齐"] }, { value = "CENTER", label = L["居中"] }, { value = "RIGHT", label = L["右对齐"] },
                    } },
                    { key = "rowSpacing", type = "slider", parentKey = "bgSettings", label = L["行间距"], min = -10, max = 30 },
                    { key = "labelX", type = "slider", parentKey = "bgSettings", label = L["标签全局X"], min = -100, max = 100 },
                    { key = "valueX", type = "slider", parentKey = "bgSettings", label = L["数值全局X"], min = -100, max = 100 },
                },
            },
            {
                kind = "table", id = "rows_table", title = L["属性行管理"],
                key = "rows", controlFactory = PLAYER_STATS_ROWS_TABLE,
                columns = {
                    { title = L["启用此行"] },
                    { title = L["名称"] },
                    { title = L["属性"] },
                    { title = L["数值字体跟随名称"] },
                    { title = L["百分比"] },
                    { title = L["选择"] .. " / " .. L["删除"] },
                },
                supportsAdd = true,
            },
            {
                kind = "settings", id = "rows", title = L["选择要编辑的行"] .. ": " .. sel .. ": " .. currentRowName,
                items = {
                    { key = "format", type = "slider", parentKey = currentRowPath, label = L["小数"], min = 0, max = 3 },
                    { key = "roles", type = "select", multiple = true, parentKey = currentRowPath, label = L["显示职责"], options = {
                        { value = "TANK", label = "TANK" }, { value = "HEALER", label = "HEALER" }, { value = "DAMAGER", label = "DAMAGER" },
                    } },
                    { key = "scenes", type = "select", multiple = true, parentKey = currentRowPath, label = L["显示场景"], options = {
                        { value = "副本内", label = L["副本内"] }, { value = "副本外", label = L["副本外"] },
                    } },
                },
            },
            {
                kind = "composite", id = "fontLabel", title = L["标签样式"],
                component = "fontgroup", key = "fontLabel", parentKey = currentRowPath, opts = { bodyOnly = true },
            },
            {
                kind = "composite", id = "fontValue", title = L["数值样式"],
                component = "fontgroup", key = "fontValue", parentKey = currentRowPath, opts = { bodyOnly = true },
            },
            {
                kind = "composite", id = "anchor", title = L["锚点设置"],
                component = "anchorgroup", key = "pos", opts = PLAYER_STATS_ANCHOR_OPTS,
            },
        },
    }



    if ExwindGrid then
        ExwindGrid.ExportReplacements = { [currentRowPath] = '"rows." .. sel' }
    end
    ExwindTools:RegisterModuleLayout(EXWIND_MODULE_KEY, layout)
end
EX_RegisterLayout()

-- =============================================================
-- 唯一 Renderer：动态双列 TextList。Runtime / World / Panel 只切换 host，
-- 使用同一个 BuildPresentation -> ApplyPresentation；Panel 不拥有任何局部输入。
-- =============================================================
-- =========================================================
-- 四、显示、预览与编辑接入 | Display, Preview and Edit Integration
-- =========================================================
local runtimeList, worldList, panelPreview, panelDock
local worldPreviewActive = false
local watchedStateKeys = {}
local SyncStateWatches

local function CopyStyle(style)
    local copy = {}
    for key, value in pairs(style or {}) do copy[key] = value end
    return copy
end

local function GetRole()
    local specID = EXState.SpecID
    return specID and specID > 0 and EXDB.SpecByID[specID] and EXDB.SpecByID[specID].role or "DAMAGER"
end

local function IsVisibleRow(conf)
    if conf.enabled ~= true then return false end
    if conf.roles and not conf.roles[GetRole()] then return false end
    local scene = IsInInstance() and "副本内" or "副本外"
    return not conf.scenes or conf.scenes[scene] == true
end

local function FormatValue(conf, internalKey, sample)
    if sample then return "12.3%", false end
    local value = internalKey ~= "None" and EXState[internalKey] or nil
    local decimals = NormalizeDecimalPlaces(conf.format)
    if conf.format ~= decimals then conf.format = decimals end
    local format = (conf.isPercent and STAT_PERCENT_FORMATS or STAT_VALUE_FORMATS)[decimals] or STAT_VALUE_FORMATS[1]
    if IsSecretValue(value) then
        if internalKey == "PStat_VersaText" or internalKey == "PStat_MovementText" then return value, true end
        return string.format(format, value), true
    end
    if value == nil then return L["N/A"], false end
    if type(value) == "string" then return value, false end
    return string.format(format, value), false
end

-- [卡片迁移边界：自定义渲染] 以下动态双列 TextList 同时服务 Runtime/World/Panel，不是设置页布局；rows 顺序、筛选、订阅和列表释放合同禁止修改。
local function BuildPresentation(sample)
    local rows, primaryStat = {}, EXDB:GetPlayerPrimaryStat() or "属性"
    for index, conf in ipairs(EX_DB.rows) do
        if IsVisibleRow(conf) then
            local label = (conf.label or ""):gsub("%%主属性", primaryStat)
            local internalKey = STAT_MAP[conf.key] or conf.key
            local value, secretText = FormatValue(conf, internalKey, sample)
            local labelStyle = CopyStyle(conf.fontLabel or GetDefaultFont())
            local valueStyle = CopyStyle(conf.syncFont and labelStyle or (conf.fontValue or GetDefaultFont()))
            rows[#rows + 1] = {
                id = tostring(index),
                label = { text = L[label] or label, style = labelStyle },
                value = { text = value, secretText = secretText, style = valueStyle },
                stateKey = internalKey,
                interaction = sample and {
                    elementID = "playerstats:row:" .. index,
                    guiTarget = "fontLabel",
                    tooltip = L["玩家属性行"],
                } or nil,
            }
        end
    end
    local bg = EX_DB.bgSettings or {}
    return {
        rows = rows,
        layout = {
            width = 220,
            rowHeight = 20,
            spacing = bg.rowSpacing or 2,
            paddingTop = 12,
            paddingBottom = 12,
            inset = 8,
            gap = 4,
            labelAlign = bg.labelAlign or "LEFT",
            valueAlign = bg.valueAlign or "RIGHT",
            labelX = bg.labelX or 0,
            valueX = bg.valueX or 0,
            backdrop = {
                shown = EX_DB.showBg == true or EX_DB.showBorder == true,
                bgFile = EX_DB.showBg and LSM:Fetch("background", bg.texture) or nil,
                edgeFile = EX_DB.showBorder and LSM:Fetch("border", bg.borderTexture) or nil,
                edgeSize = bg.edgeSize or 9,
                insetLeft = bg.inset or 8,
                insetRight = bg.inset or 8,
                insetTop = bg.inset or 8,
                insetBottom = bg.inset or 8,
                bgColor = { r = bg.bgColorR or 0, g = bg.bgColorG or 0, b = bg.bgColorB or 0, a = EX_DB.showBg and (bg.bgColorA or 0.5) or 0 },
                borderColor = { r = bg.borderColorR or 1, g = bg.borderColorG or 1, b = bg.borderColorB or 1, a = EX_DB.showBorder and (bg.borderColorA or 1) or 0 },
            },
        },
    }
end

local function ApplyPresentation(list, presentation, point, host)
    if not list then return nil end
    local bounds = list:SetItems(presentation.rows, presentation.layout)
    list.root:ClearAllPoints()
    list.root:SetPoint(point or "BOTTOMLEFT", host or list.root:GetParent(), point or "BOTTOMLEFT", 0, 0)
    return bounds
end

local function RefreshSettingsPanel()
    if EXUI.MainFrame and EXUI.MainFrame:IsShown() and EXUI.RefreshContent then
        EXUI:RefreshContent()
    end
end

EnsureAnchor = function()
    if anchorController then
        anchorFrame = anchorController:Ensure(); return anchorFrame
    end
    anchorController = ExwindTools:CreateAnchorController({
        moduleKey = EXWIND_MODULE_KEY,
        frameName = "ExwindPlayerStatsAnchor",
        title = L["玩家属性面板"],
        getDB = function() return EX_DB.pos end,
        offsetXKey = "x",
        offsetYKey = "y",
        defaultOffsetX = EX_DEFAULTS.root.pos.x,
        defaultOffsetY = EX_DEFAULTS.root.pos.y,
        attachEnabledKey = "attachToCustom",
        attachTargetKey = "customAttachTarget",
        syncWidgets = { "x", "y", "attachToCustom", "customAttachTarget" },
        widgetRanges = { x = { min = -1000, max = 1000, step = 1 }, y = { min = -1000, max = 1000, step = 1 } },
        getAnchorPoint = function() return (EX_DB.pos and EX_DB.pos.point) or "BOTTOMLEFT" end,
        getRelativePoint = function() return (EX_DB.pos and EX_DB.pos.point) or "BOTTOMLEFT" end,
        initialWidth = 220,
        initialHeight = 100,
        onPositionSaved = RefreshSettingsPanel,
        onCreateFrame = function(_, frame) frame:Hide() end,
    })
    anchorFrame = anchorController:Ensure()
    return anchorFrame
end

local function EnsureRuntimeList()
    if not runtimeList then runtimeList = EXUI:CreateTextList(EnsureAnchor(), "runtime", EXWIND_MODULE_KEY) end
    return runtimeList
end

local function RefreshRuntime()
    if worldPreviewActive then return end
    local bounds = ApplyPresentation(EnsureRuntimeList(), BuildPresentation(false), "BOTTOMLEFT", EnsureAnchor())
    EnsureAnchor():SetSize(bounds.width, bounds.height)
    EnsureAnchor():Show()
end

-- Runtime / World / Panel 都使用同一份双列 TextList presentation。设置页绝不能
-- 把 label/value 拼成单 Text 后再自行居中，否则对齐、XY、行距和背景会偏离实际显示。
ApplyPlayerStatsLiveVisual = function()
    if not panelPreview then return false end
    local rowsByID = {}
    for _, row in ipairs(BuildPresentation(true).rows) do rowsByID[row.id] = row end
    return panelPreview:ReapplyExistingItems(function(id) return rowsByID[tostring(id)] end)
end

local function RefreshPanelPreview()
    if panelPreview then
        local bounds = ApplyPresentation(panelPreview, BuildPresentation(true), "CENTER", panelDock)
        if panelDock then
            panelDock:SetHeight(math.max(220, bounds.height + 28))
        end
    end
end

local function HandlePanelPreviewIntent(intent)
    if type(intent) ~= "table" or (intent.type ~= "elementClicked" and intent.type ~= "elementRightClicked") then return false end
    local rowID = type(intent.elementID) == "string" and intent.elementID:match("^playerstats:row:(%d+)$")
    local rowIndex = tonumber(rowID)
    if not rowIndex or not EX_DB.rows[rowIndex] or intent.guiTarget ~= "fontLabel" then return false end
    EX_DB.selectedRow = rowIndex
    EX_RegisterLayout()
    EXUI:RefreshContent()
    return EXUI:FocusCurrentModuleGridKey(EXWIND_MODULE_KEY, "fontLabel")
end

local function ShowPanelPreview(dock)
    if panelPreview then panelPreview:Release() end
    panelDock = dock
    panelPreview = EXUI:CreateTextList(dock, "panel", EXWIND_MODULE_KEY, { onIntent = HandlePanelPreviewIntent })
    RefreshPanelPreview()
end

local function ReleasePanelPreview()
    if panelPreview then
        panelPreview:Release(); panelPreview = nil
    end
    panelDock = nil
end

local function RenderWorld(host)
    worldPreviewActive = true
    if runtimeList then runtimeList.root:Hide() end
    host:Show()
    if worldList then worldList:Release() end
    worldList = EXUI:CreateTextList(host, "world", EXWIND_MODULE_KEY)
    local bounds = ApplyPresentation(worldList, BuildPresentation(true), "BOTTOMLEFT", host)
    host:SetSize(bounds.width, bounds.height)
end

local function ReleaseWorld()
    if worldList then
        worldList:Release(); worldList = nil
    end
    worldPreviewActive = false
    RefreshRuntime()
end

local function GetWorldBounds()
    return worldList and worldList.bounds or { width = 220, height = 100, anchorOffsetX = 0, anchorOffsetY = 0 }
end

-- 属性数值更新会频繁发生。它们只重套现有行，绝不能在左键拖动期间销毁并重建
-- EditMode 的 SelectionFrame；只有行数量/纵向几何实际变化时才请求 Core 重物化。
local function RefreshAll(refreshEditWorld)
    RefreshRuntime()
    RefreshPanelPreview()
    if worldList then
        local host = worldList.root:GetParent()
        local bounds = ApplyPresentation(worldList, BuildPresentation(true), "BOTTOMLEFT", host)
        host:SetSize(bounds.width, bounds.height)
    end
    if refreshEditWorld == true then
        EXUI:RefreshEditableModule("ExwindTools", "playerstats")
    end
end

local function ReapplyExistingList(list, sample)
    if not list or type(list.ReapplyExistingItems) ~= "function" then return end
    local rows = {}
    for _, row in ipairs(BuildPresentation(sample).rows) do rows[tostring(row.id)] = row end
    list:ReapplyExistingItems(function(id) return rows[tostring(id)] end)
end

local function RequiresFullSurfaceRefresh(changedPath)
    if type(changedPath) ~= "string" or changedPath == "" then return true end
    if changedPath == "showBg" or changedPath == "showBorder" then return true end
    if changedPath:match("^bgSettings%.") or changedPath == "pos" or changedPath:match("^pos%.") then return true end
    -- 这些字段会改变实际行集合或订阅的属性来源，不能只重套已有文字。
    return changedPath:match("^rows%.%d+%.(enabled|roles|scenes|key)$") ~= nil
end

local function RefreshActiveSurfaces(_, changedPath, phase)
    -- selectedRow 只是设置页当前编辑上下文；写入后必须重新登记动态 rows.N 路径，
    -- 否则名称、属性和字体控件仍会写到先前选中的行。
    if changedPath == "selectedRow" then
        if phase == "committed" then
            EX_RegisterLayout()
            RefreshSettingsPanel()
        end
        return
    end

    if (changedPath == "pos" or (type(changedPath) == "string" and changedPath:match("^pos%."))) and anchorController then
        anchorController:ApplyPosition()
    end

    if RequiresFullSurfaceRefresh(changedPath) then
        if type(changedPath) == "string" and changedPath:match("^rows%.%d+%.(enabled|roles|scenes|key)$") then
            SyncStateWatches()
        end
        local changesWorldGeometry = type(changedPath) == "string"
            and (changedPath == "bgSettings.rowSpacing"
                or changedPath:match("^rows%.%d+%.(enabled|roles|scenes|key)$") ~= nil)
        RefreshAll(changesWorldGeometry)
        return
    end

    -- 单行文字内容与字体样式不改变行拓扑或双列布局，只重套已物化项目。
    if ApplyPlayerStatsLiveVisual then ApplyPlayerStatsLiveVisual() end
    ReapplyExistingList(worldList, true)
    ReapplyExistingList(runtimeList, false)
end

EXUI:RegisterModuleValueController(EXWIND_MODULE_KEY, { RefreshActiveSurfaces = RefreshActiveSurfaces })

-- =========================================================
-- 六、事件订阅与配置刷新 | Events and Configuration Refresh
-- =========================================================
SyncStateWatches = function()
    local wanted = {}
    for _, row in ipairs(BuildPresentation(false).rows) do
        if row.stateKey and row.stateKey ~= "None" then wanted[row.stateKey] = true end
    end
    for key in pairs(watchedStateKeys) do
        if not wanted[key] then
            ExwindTools:UnwatchState(key, "PlayerStats." .. key)
            watchedStateKeys[key] = nil
        end
    end
    for key in pairs(wanted) do
        if not watchedStateKeys[key] then
            watchedStateKeys[key] = true
            ExwindTools:WatchState(key, "PlayerStats." .. key, RefreshAll)
        end
    end
end

EnsureAnchor()
EnsureRuntimeList()
SyncStateWatches()
RefreshRuntime()

ExwindTools:RegisterModulePreview(EXWIND_MODULE_KEY, {
    mount = function(dock) ShowPanelPreview(dock) end,
    update = function() RefreshPanelPreview() end,
    release = function() ReleasePanelPreview() end,
})

EXUI:RegisterEditableModule({
    addon = "ExwindTools",
    key = "playerstats",
    name = L["玩家属性面板"],
    settingsPage = EXWIND_MODULE_KEY,
    orientation = "VERTICAL",
    worldAnchorMode = "semantic-root",
    editOverlay = { titleFontSize = 28 },
    getAnchor = EnsureAnchor,
    RenderWorld = RenderWorld,
    ReleaseWorld = ReleaseWorld,
    GetWorldBounds = GetWorldBounds,
})

ExwindTools:WatchState("SpecID", EXWIND_MODULE_KEY, function()
    SyncStateWatches()
    RefreshAll(true)
end)

ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", EXWIND_MODULE_KEY, function()
    SyncStateWatches()
    RefreshAll(true)
end)

ExwindTools:WatchState(EXWIND_MODULE_KEY .. ".ButtonClicked", EXWIND_MODULE_KEY, function(info)
    if not info or not info.key then return end
    local selected = tonumber(EX_DB.selectedRow) or 1
    if selected < 1 then selected = 1 end
    if selected > #EX_DB.rows then selected = #EX_DB.rows end
    if info.key == "btn_up" and selected > 1 then
        EX_DB.rows[selected], EX_DB.rows[selected - 1] = EX_DB.rows[selected - 1], EX_DB.rows[selected]
        EX_DB.selectedRow = selected - 1
        EX_RegisterLayout(); EXUI:RefreshContent()
    elseif info.key == "btn_down" and selected < #EX_DB.rows then
        EX_DB.rows[selected], EX_DB.rows[selected + 1] = EX_DB.rows[selected + 1], EX_DB.rows[selected]
        EX_DB.selectedRow = selected + 1
        EX_RegisterLayout(); EXUI:RefreshContent()
    elseif info.key == "btn_add" then
        table.insert(EX_DB.rows, {
            enabled = true,
            label = L["新属性"],
            key = "无",
            isPercent = true,
            format = 1,
            syncFont = true,
            roles = { TANK = true, HEALER = true, DAMAGER = true },
            scenes = { ["副本内"] = true, ["副本外"] = true },
            fontLabel = GetDefaultFont(),
            fontValue = GetDefaultFont()
        })
        EX_DB.selectedRow = #EX_DB.rows
        EX_RegisterLayout(); EXUI:RefreshContent()
    elseif info.key == "btn_delete" and #EX_DB.rows > 1 then
        table.remove(EX_DB.rows, selected)
        EX_DB.selectedRow = math.max(1, selected - 1)
        EX_RegisterLayout(); EXUI:RefreshContent()
    end
    SyncStateWatches()
    RefreshAll(true)
end)

ExwindTools:ReportReady(EXWIND_MODULE_KEY)
