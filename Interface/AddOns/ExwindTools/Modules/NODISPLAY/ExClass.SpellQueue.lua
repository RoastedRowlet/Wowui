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
local GM = ExwindTools.GUIMetrics
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

-- =========================================================
-- 三、GUI 声明 | GUI Declarations
-- =========================================================
local function EX_RegisterLegacyLayout()
    -- [声明迁移边界：设置页] 控件只声明一次；专精紧凑行由 Core 按原 moduleKey/parentKey/key 语义呈现。
    -- AI/固定模式的 key、专精 parentKey 切换、专精业务顺序与 CVar 回调禁止修改。
    local liveStatus = { key = "live_status", type = "description", label = GetCurrentInfo() }
    local coreItems = {
        { key = "enabled", type = "switch", label = L["开启功能"] },
        { key = "aiMode", type = "switch", label = "|cff00ffff" .. L["启用 AI 智能模式"] .. "|r" },
        { key = "globalFixed", type = "input", label = L["全局默认延迟值 (固定)"] },
    }
    local plateItems = {
        { key = "250", type = "input", label = MakeSpecLabel(135770, "C41E3A", "鲜血"), parentKey = "specs" },
        { key = "251", type = "input", label = MakeSpecLabel(135773, "C41E3A", "冰霜"), parentKey = "specs" },
        { key = "252", type = "input", label = MakeSpecLabel(135775, "C41E3A", "邪恶"), parentKey = "specs" },
        { key = "73", type = "input", label = MakeSpecLabel(132341, "C79C6E", "防护"), parentKey = "specs" },
        { key = "71", type = "input", label = MakeSpecLabel(132355, "C79C6E", "武器"), parentKey = "specs" },
        { key = "72", type = "input", label = MakeSpecLabel(132347, "C79C6E", "狂怒"), parentKey = "specs" },
        { key = "66", type = "input", label = MakeSpecLabel(236264, "F48CBA", "防护"), parentKey = "specs" },
        { key = "70", type = "input", label = MakeSpecLabel(135873, "F48CBA", "惩戒"), parentKey = "specs" },
        { key = "65", type = "input", label = MakeSpecLabel(135920, "F48CBA", "神圣"), parentKey = "specs" },
    }
    local mailItems = {
        { key = "255", type = "input", label = MakeSpecLabel(461113, "ABD473", "生存"), parentKey = "specs" },
        { key = "254", type = "input", label = MakeSpecLabel(236179, "ABD473", "射击"), parentKey = "specs" },
        { key = "253", type = "input", label = MakeSpecLabel(461112, "ABD473", "野兽控制"), parentKey = "specs" },
        { key = "262", type = "input", label = MakeSpecLabel(136048, "0070DD", "元素"), parentKey = "specs" },
        { key = "263", type = "input", label = MakeSpecLabel(237581, "0070DD", "增强"), parentKey = "specs" },
        { key = "264", type = "input", label = MakeSpecLabel(136052, "0070DD", "恢复"), parentKey = "specs" },
        { key = "1467", type = "input", label = MakeSpecLabel(4511811, "33937F", "湮灭"), parentKey = "specs" },
        { key = "1473", type = "input", label = MakeSpecLabel(5198700, "33937F", "增辉"), parentKey = "specs" },
        { key = "1468", type = "input", label = MakeSpecLabel(4511812, "33937F", "恩护"), parentKey = "specs" },
    }
    local leatherItems = {
        { key = "581", type = "input", label = MakeSpecLabel(1247265, "A330C9", "复仇"), parentKey = "specs" },
        { key = "577", type = "input", label = MakeSpecLabel(1247264, "A330C9", "浩劫"), parentKey = "specs" },
        { key = "1480", type = "input", label = MakeSpecLabel(7455385, "A330C9", "噬灭"), parentKey = "specs" },
        { key = "260", type = "input", label = MakeSpecLabel(236286, "FFF468", "狂徒"), parentKey = "specs" },
        { key = "259", type = "input", label = MakeSpecLabel(236270, "FFF468", "奇袭"), parentKey = "specs" },
        { key = "261", type = "input", label = MakeSpecLabel(132320, "FFF468", "敏锐"), parentKey = "specs" },
        { key = "268", type = "input", label = MakeSpecLabel(608951, "00FF98", "酒仙"), parentKey = "specs" },
        { key = "269", type = "input", label = MakeSpecLabel(608953, "00FF98", "踏风"), parentKey = "specs" },
        { key = "270", type = "input", label = MakeSpecLabel(608952, "00FF98", "织雾"), parentKey = "specs" },
        { key = "104", type = "input", label = MakeSpecLabel(132276, "FF7C0A", "守护"), parentKey = "specs" },
        { key = "103", type = "input", label = MakeSpecLabel(132115, "FF7C0A", "野性"), parentKey = "specs" },
        { key = "102", type = "input", label = MakeSpecLabel(136096, "FF7C0A", "平衡"), parentKey = "specs" },
        { key = "105", type = "input", label = MakeSpecLabel(136041, "FF7C0A", "恢复"), parentKey = "specs" },
    }
    local clothItems = {
        { key = 64, type = "input", label = MakeSpecLabel(135846, "3FC7EB", "冰霜"), parentKey = "specs" },
        { key = 63, type = "input", label = MakeSpecLabel(135810, "3FC7EB", "火焰"), parentKey = "specs" },
        { key = 62, type = "input", label = MakeSpecLabel(135932, "3FC7EB", "奥术"), parentKey = "specs" },
        { key = 267, type = "input", label = MakeSpecLabel(136186, "8788EE", "毁灭"), parentKey = "specs" },
        { key = 265, type = "input", label = MakeSpecLabel(136145, "8788EE", "痛苦"), parentKey = "specs" },
        { key = "266", type = "input", label = MakeSpecLabel(136172, "8788EE", "恶魔学识"), parentKey = "specs" },
        { key = 256, type = "input", label = MakeSpecLabel(135940, "FFFFFF", "戒律"), parentKey = "specs" },
        { key = 257, type = "input", label = MakeSpecLabel(237542, "FFFFFF", "神圣"), parentKey = "specs" },
        { key = 258, type = "input", label = MakeSpecLabel(136207, "FFFFFF", "暗影"), parentKey = "specs" },
    }
    local items = {
        coreItems[1], coreItems[2], coreItems[3],
        plateItems[1], plateItems[2], plateItems[3], plateItems[5], plateItems[6], plateItems[4],
        plateItems[9], plateItems[7], plateItems[8],
        mailItems[3], mailItems[2], mailItems[1], mailItems[4], mailItems[5], mailItems[6],
        mailItems[7], mailItems[9], mailItems[8],
        leatherItems[2], leatherItems[1], leatherItems[3], leatherItems[5], leatherItems[4], leatherItems[6],
        leatherItems[7], leatherItems[8], leatherItems[9], leatherItems[12], leatherItems[11], leatherItems[10], leatherItems[13],
        clothItems[3], clothItems[2], clothItems[1], clothItems[5], clothItems[6], clothItems[4],
        clothItems[7], clothItems[8], clothItems[9],
    }






    -- 3. 逻辑适配区 (只在注册前，刷新受 AI 模式影响的内容)
    -- 注意：这里使用 lua 本地逻辑更新 parentKey，不改变 layout 的静态结构
    local targetStorage = EX_DB.aiMode and "specsAI" or "specs"
    local suffix = EX_DB.aiMode and " |cff00ffff(AI)|r" or ""

    for i = 1, #items do
        local item = items[i]

        -- 全局默认值切换 (双向修复)
        -- 无论当前 layout 里写的是 globalFixed 还是 globalOffset，都根据 aiMode 强制修正
        if item.key == "globalFixed" or item.key == "globalOffset" then
            if EX_DB.aiMode then
                item.key = "globalOffset"
                item.baseLabel = item.baseLabel or item.label
                item.label = L["全局延迟偏移 |cff00ffff(AI)|r"]
            else
                item.key = "globalFixed"
                item.baseLabel = item.baseLabel or item.label
                item.label = L["全局默认延迟值 (固定)"]
            end
        end

        -- 处理所有专精对应的输入框
        if item.parentKey == "specs" or item.parentKey == "specsAI" then
            item.parentKey = targetStorage
            -- 动态追加 AI 标识
            if EX_DB.aiMode then
                item.baseLabel = item.baseLabel or item.label
                if item.label and not item.label:find("AI") then
                    item.label = suffix .. item.label
                end
            else
                -- 还原 Label (如果有 baseLabel)
                if item.baseLabel then item.label = item.baseLabel end
            end
        end
    end

    local layout = {
        version = 1,
        description = L["AI模式：容限 = 延迟 + 偏移。固定模式：容限 = 设定值。"],
        sections = {
            {
                kind = "settings",
                id = "overview",
                title = L["全职业延迟容限 (SpellQueueWindow)"],
                description = liveStatus,
                items = {},
            },
            { kind = "settings", id = "core", title = L["核心控制"], items = coreItems },
            { kind = "settings", id = "plate", title = L["板甲职业"], items = plateItems },
            { kind = "settings", id = "mail", title = L["锁甲职业"], items = mailItems },
            { kind = "settings", id = "leather", title = L["皮甲职业"], items = leatherItems },
            { kind = "settings", id = "cloth", title = L["布甲职业"], items = clothItems },
        },
    }

    ExwindTools:RegisterModuleLayout(EXWIND_MODULE_KEY, layout)
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

local function BuildSpecCard(id, title, source)
    local columns = { { width = 104 } }
    local cells = {
        { id = id .. ".classCell", kind = "cell", children = {
            { id = id .. ".className", kind = "text", textSource = "className" },
        } },
    }
    for slot = 1, source == "leather" and 4 or 3 do
        columns[#columns + 1] = { weight = 1 }
        cells[#cells + 1] = { id = id .. ".specCell" .. slot, kind = "cell", children = {
            { id = id .. ".spec" .. slot, kind = "control", ref = "spec" .. slot,
                controlType = "input", visible = slot == 4 and "hasFourthSpec" or nil },
        } }
    end
    return {
        id = id, kind = "card", title = title, children = {
            { id = id .. ".columns", kind = "columns",
                columns = columns,
                children = {
                    { id = id .. ".rows", kind = "repeat", source = source,
                        template = { id = id .. ".row", kind = "row", separator = true, children = cells } },
                },
            },
        },
    }
end

-- =========================================================
-- 三、GUI 声明 | GUI Declarations — V2 Page Adapters / V2 页面适配器
-- =========================================================
local function BuildV2Declaration()
    return {
        version = 2,
        cards = {
            {
                id = "queue.core", kind = "card", title = L["全职业延迟容限 (SpellQueueWindow)"], children = {
                    { id = "queue.status", kind = "hint", textSource = "status" },
                    { id = "queue.help", kind = "hint", text = L["AI模式：容限 = 延迟 + 偏移。固定模式：容限 = 设定值。"] },
                    { id = "queue.coreRow", kind = "row", children = {
                        { id = "queue.enabled", kind = "control", ref = "enabled", controlType = "checkbox", width = 150 },
                        { id = "queue.aiMode", kind = "control", ref = "aiMode", controlType = "checkbox", width = 210 },
                        { id = "queue.global", kind = "control", ref = "global", controlType = "input", weight = 1 },
                    } },
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
    local owner = { controls = {}, components = {}, actions = {}, predicates = {}, sources = {}, texts = {} }
    local session
    function owner:AttachSession(value) session = value end
    local function RefreshPage() if session then session:Refresh() end end
    local function ReleaseControl(widget)
        if _G.ExwindGrid and _G.ExwindGrid.ReleaseWidgetInstance then
            _G.ExwindGrid:ReleaseWidgetInstance(widget)
        end
    end
    local function Commit(binding, value)
        if binding.read() == value then return false end
        EXUI:CommitModuleValue({
            moduleKey = EXWIND_MODULE_KEY,
            path = binding.path,
            readValue = binding.read,
            writeValue = binding.write,
        }, value)
        RefreshPage()
        return true
    end
    local function Checkbox(label, key)
        return {
            mount = function(host)
                return EXUI:CreateCheckbox(host, label, EX_DB[key] == true, function(value)
                    Commit({ path = key, read = function() return EX_DB[key] end,
                        write = function(nextValue) EX_DB[key] = nextValue end }, value == true)
                end)
            end,
            update = function(widget) widget:SetChecked(EX_DB[key] == true) end,
            release = ReleaseControl,
        }
    end
    local function Input(bindingFor, labelFor)
        return {
            mount = function(host, context)
                local binding = bindingFor(context.scope)
                local widget = EXUI:CreateEditBox(host, tostring(binding.read() or ""), 180, GM.size.inputHeight,
                    labelFor(context.scope), {
                        labelPos = "left",
                        onEnter = function(text) Commit(bindingFor(context.scope), text or "") end,
                        onEditFocusLost = function(text) Commit(bindingFor(context.scope), text or "") end,
                    })
                return widget
            end,
            update = function(widget, context)
                local binding = bindingFor(context.scope)
                if widget.label then widget.label:SetText(labelFor(context.scope)) end
                local editBox = widget.editBox or widget
                local text = tostring(binding.read() or "")
                if (not editBox.HasFocus or not editBox:HasFocus()) and editBox:GetText() ~= text then
                    editBox:SetText(text)
                end
            end,
            measure = function(widget, context, width)
                local gap = GM.space.settingsV2Gap
                local labelWidth = math.min(math.ceil(widget.label:GetUnboundedStringWidth()),
                    math.max(1, width - GM.size.sliderInputWidth - gap))
                widget.label:SetWidth(labelWidth)
                widget.label:SetWordWrap(true)
                widget._exV2LabelWidth = labelWidth
                return math.max(GM.size.inputHeight, math.ceil(widget.label:GetStringHeight()))
            end,
            layout = function(widget, context, width, height)
                local gap = GM.space.settingsV2Gap
                local labelWidth = widget._exV2LabelWidth or 0
                widget:ClearAllPoints()
                widget:SetPoint("TOPRIGHT", widget:GetParent(), "TOPRIGHT", 0,
                    -(height - GM.size.inputHeight) / 2)
                widget:SetSize(math.max(1, width - labelWidth - gap), GM.size.inputHeight)
                widget.label:ClearAllPoints()
                widget.label:SetPoint("RIGHT", widget, "LEFT", -gap, 0)
                widget.label:SetJustifyH("LEFT")
                widget.label:SetWidth(labelWidth)
            end,
            release = ReleaseControl,
        }
    end

    owner.controls.enabled = Checkbox(L["开启功能"], "enabled")
    owner.controls.aiMode = Checkbox("|cff00ffff" .. L["启用 AI 智能模式"] .. "|r", "aiMode")
    owner.controls.global = Input(function()
        local key = EX_DB.aiMode and "globalOffset" or "globalFixed"
        return { path = key, read = function() return EX_DB[key] end,
            write = function(value) EX_DB[key] = value end }
    end, function()
        return EX_DB.aiMode and L["全局延迟偏移 |cff00ffff(AI)|r"] or L["全局默认延迟值 (固定)"]
    end)
    for slot = 1, 4 do
        local specSlot = slot
        owner.controls["spec" .. specSlot] = Input(function(scope)
            local spec = scope.item.specs[specSlot]
            if not spec then
                return { path = "specs.__unused", read = function() return nil end, write = function() end }
            end
            local storageKey = EX_DB.aiMode and "specsAI" or "specs"
            local storage = EX_DB[storageKey]
            return { path = storageKey .. "." .. spec[1], read = function() return storage[spec[1]] end,
                write = function(value) storage[spec[1]] = value end }
        end, function(scope)
            local spec = scope.item.specs[specSlot]
            if not spec then return "" end
            local prefix = EX_DB.aiMode and "|cff00ffff(AI)|r " or ""
            return prefix .. MakeSpecLabel(spec[2], spec[3], spec[4])
        end)
    end
    owner.sources.plate = function() return SPEC_GROUPS.plate end
    owner.sources.mail = function() return SPEC_GROUPS.mail end
    owner.sources.leather = function() return SPEC_GROUPS.leather end
    owner.sources.cloth = function() return SPEC_GROUPS.cloth end
    owner.texts.status = function() return GetCurrentInfo() end
    owner.texts.className = function(scope) return L[scope.item.class] end
    owner.predicates.hasFourthSpec = function(scope) return scope.item.specs[4] ~= nil end
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

    -- 定向更新状态文本，防止滚动条重置
    if ExwindTools.Grid and ExwindTools.Grid.Widgets then
        local w = ExwindTools.Grid.Widgets["live_status"]
        if w and w.text then w.text:SetText(GetCurrentInfo()) end
    end

end

EXUI:RegisterModuleValueController(EXWIND_MODULE_KEY, { RefreshActiveSurfaces = RefreshActiveSurfaces })

-- 监听天赋/职业变动 (核心框架广播)
local function OnIdentityChanged()
    EX_RegisterLayout() -- 重新生成布局以更新当前状态文字
    ApplySpellQueue()

    -- 如果主 UI 正在显示当前模块，则强制刷新以更新界面文字
    if ExwindTools.UI and ExwindTools.UI.MainFrame and ExwindTools.UI.MainFrame:IsShown() and ExwindTools.UI.CurrentModule == EXWIND_MODULE_KEY then
        ExwindTools.UI:RefreshContent()
    end
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
