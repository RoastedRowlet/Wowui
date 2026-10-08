-- [[ 自动购买 ]]
-- { Key = "ExTools.AutoBuy", Name = "自动购买", Desc = "在商人处自动购买预设或自定义的物品（如钥石地图、消耗品等）。", Category = 4 },

-- =========================================================
-- 一、模块标识与依赖引用 | Module Identity and Dependencies
-- =========================================================
local ExwindTools = _G.ExwindTools
local EXDB = _G.EXDB
if not ExwindTools then return end
local EXState = ExwindTools.State
local L = (ExwindTools and ExwindTools.L) or setmetatable({}, { __index = function(_, key) return key end })

-- 1. 识别 Key
local EXWIND_MODULE_KEY = "ExTools.AutoBuy"

-- 2. 载入检查
if not ExwindTools:IsModuleEnabled(EXWIND_MODULE_KEY) then return end

-- 3. 数据默认值与 DB 初始化
-- =========================================================
-- 二、默认配置与配置访问 | Defaults and Configuration Access
-- =========================================================
local EXWIND_DEFAULTS = {
    enabled = true,
    Items = {},       -- 存储 ID -> {enabled, quantity}
    CustomItems = {}, -- 存储 ID -> {enabled, quantity}
}
local EX_DB = ExwindTools:GetModuleDB(EXWIND_MODULE_KEY, EXWIND_DEFAULTS)

-- 静态配置数据
local PRESET_ITEMS = {
    -- 钥石箱
    { id = 151060, buy = 1, cat = "key", name = "" },
    -- 层数
    { id = 166381, buy = 5, cat = "key" }, { id = 166380, buy = 5, cat = "key" },
    { id = 166379, buy = 5, cat = "key" }, { id = 166378, buy = 5, cat = "key" },
    { id = 166377, buy = 5, cat = "key" }, { id = 159694, buy = 5, cat = "key" },
    { id = 159695, buy = 5, cat = "key" }, { id = 159696, buy = 5, cat = "key" },
    { id = 159697, buy = 5, cat = "key" }, { id = 159698, buy = 5, cat = "key" },

    { id = 271947, buy = 5,   cat = "key" }, -- 密谋
    { id = 271960, buy = 5,   cat = "key" }, -- 夺目
    { id = 271952, buy = 5,   cat = "key" }, -- 虚空
    { id = 271958, buy = 5,   cat = "key" }, -- 洞穴
    { id = 201350, buy = 5,   cat = "key" }, -- 红玉
    { id = 166391, buy = 5,   cat = "key" }, -- 诸王
    { id = 166394, buy = 5,   cat = "key" }, -- 神庙
    { id = 271944, buy = 5,   cat = "key" }, -- 毒牙


    { id = 241288, buy = 400, cat = "food" },
    { id = 241292, buy = 400, cat = "food" },
    { id = 241300, buy = 200, cat = "food" },
    { id = 241302, buy = 200, cat = "food" },
    { id = 241304, buy = 400, cat = "food" },
    { id = 241308, buy = 400, cat = "food" },
    { id = 241320, buy = 200, cat = "food" },


    { id = 243734, buy = 100, cat = "food" }, { id = 243738, buy = 20, cat = "food" },
    { id = 241326, buy = 200, cat = "food" }, { id = 241324, buy = 200, cat = "food" },
}

-- =========================================================
-- [v4.2] 注册与配置
-- =========================================================



-- 2. Grid 布局 (核心)
-- =========================================================
-- 三、GUI 声明 | GUI Declarations
-- =========================================================
local pendingItemInfo = {}
local function ItemTextCell(itemID)
    local name, _, quality = C_Item.GetItemInfo(itemID)
    if not name and not pendingItemInfo[itemID] then
        pendingItemInfo[itemID] = true
        C_Item.RequestLoadItemDataByID(itemID)
    end
    if name then
        local _, _, _, hex = C_Item.GetItemQualityColor(quality or 1)
        name = "|c" .. hex .. name .. "|r"
    end
    return {
        text = name or ("ID: " .. itemID),
        icon = C_Item.GetItemIconByID(itemID) or 134400,
        itemID = itemID,
    }
end

local function EX_RegisterLayout()
    -- 物品身份由正式表格的只读 text/icon 单元格显示；启用、数量、增删
    -- 继续使用原记录、配置路径和业务回调。
    local layout = {
        version = 1,
        title = L["自动购买 (Auto Buy)"],
        description = L["当打开商人界面时，自动购买背包中缺少的物品 (自动补齐到设置数量)"],
        sections = {
            {
                kind = "table",
                id = "general",
                title = L["通用设置"],
                columns = {
                    { title = L["启用"] },
                    { title = L["物品"] },
                    { title = L["数量"] },
                    { title = L["操作"] },
                },
                supportsAdd = true,
                add = {
                    cells = {
                        { text = "" },
                        { key = "addID", type = "input", label = L["输入 ID"] },
                        { text = "" },
                        { key = "addItem", type = "button", label = L["添加"] },
                    },
                },
                records = {},
            },
        },
    }

    local records = layout.sections[1].records

    -- 渲染自定义列表
    local customList = {}
    for id, _ in pairs(EX_DB.CustomItems) do table.insert(customList, tonumber(id)) end
    table.sort(customList)

    for _, id in ipairs(customList) do
        records[#records + 1] = { cells = {
            {
                key = "custom_enabled_" .. id,
                parentKey = "CustomItems", subKey = id, type = "itemenabled", itemID = id,
            },
            ItemTextCell(id),
            {
                key = "custom_quantity_" .. id,
                parentKey = "CustomItems", subKey = id, type = "itemquantity", itemID = id,
            },
            {
                key = "custom_delete_" .. id,
                parentKey = "CustomItems", subKey = id, type = "itemdelete", itemID = id,
                canDelete = true,
            },
        } }
    end

    local cats = { { k = "food", n = L["消耗品"] }, { k = "key", n = L["钥石设置"] }, { k = "map", n = L["副本地图"] } }
    for _, cat in ipairs(cats) do
        -- [Core] 如果是 Key 或 Map 分类且当前不是 Beta 环境，则隐藏
        local isBetaOnly = (cat.k == "key" or cat.k == "map")
        local shouldShow = (not isBetaOnly) or ExwindTools.IsBeta

        if shouldShow then
            for _, it in ipairs(PRESET_ITEMS) do
                if it.cat == cat.k then
                    if not EX_DB.Items[it.id] then EX_DB.Items[it.id] = { enabled = true, quantity = it.buy } end
                    records[#records + 1] = { cells = {
                        {
                            key = "preset_enabled_" .. it.id,
                            parentKey = "Items", subKey = it.id, type = "itemenabled", itemID = it.id,
                        },
                        ItemTextCell(it.id),
                        {
                            key = "preset_quantity_" .. it.id,
                            parentKey = "Items", subKey = it.id, type = "itemquantity", itemID = it.id,
                        },
                        { text = "" },
                    } }
                end
            end
        end
    end

    ExwindTools:RegisterModuleLayout(EXWIND_MODULE_KEY, layout)
    return layout
end

-- 3. 立即注册
EX_RegisterLayout()

ExwindTools:RegisterEvent("GET_ITEM_INFO_RECEIVED", EXWIND_MODULE_KEY, function(_, itemID, success)
    if not pendingItemInfo[itemID] then return end
    pendingItemInfo[itemID] = nil
    if not success then return end
    local layout = EX_RegisterLayout()
    local ui = ExwindTools.UI
    if ui.CurrentPage == "ModuleSettings" and ui.CurrentModule == EXWIND_MODULE_KEY then
        local session = ui.ActivePageFrame and ui.ActivePageFrame._exCardSession
        if session then session:ReplaceSettingsSection("general", layout.sections[1]) end
    end
end)

-- =========================================================
-- 逻辑绑定：通过事件处理添加与删除
-- =========================================================

-- 1. 处理按钮点击 (添加物品)
ExwindTools:WatchState(EXWIND_MODULE_KEY .. ".ButtonClicked", EXWIND_MODULE_KEY, function(data)
    if data.key == "addItem" then
        local idStr = EX_DB.addID
        local id = tonumber(idStr)
        if id and id > 0 then
            EX_DB.CustomItems[id] = { enabled = true, quantity = 5 }
            EX_DB.addID = "" -- 清空
            EX_RegisterLayout()
            ExwindTools.UI:RefreshContent()
        end
    end
end)

-- 2. 处理 ItemConfig 组件上报的删除事件
ExwindTools:WatchState(EXWIND_MODULE_KEY .. ".ItemConfigDelete", EXWIND_MODULE_KEY, function(data)
    local id = tonumber(data.key)
    if id and EX_DB.CustomItems[id] then
        EX_DB.CustomItems[id] = nil
        EX_RegisterLayout()
        ExwindTools.UI:RefreshContent()
    end
end)

-- =========================================================
-- 五、业务状态与功能逻辑 | Business State and Logic
-- =========================================================
local function GetCount(id)
    local c = 0
    local maxBagIndex = 4
    if Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag then
        maxBagIndex = Enum.BagIndex.ReagentBag
    else
        maxBagIndex = 5
    end

    for b = 0, maxBagIndex do
        for s = 1, C_Container.GetContainerNumSlots(b) do
            local inf = C_Container.GetContainerItemInfo(b, s)
            if inf and inf.itemID == id then c = c + inf.stackCount end
        end
    end
    return c
end

local function DoBuy(id, target)
    local have = GetCount(id)
    local need = target - have
    if need <= 0 then return false end

    local num = GetMerchantNumItems()
    for i = 1, num do
        if GetMerchantItemID(i) == id then
            local _, _, _, _, _, _, _, stack = C_Item.GetItemInfo(id)
            stack = stack or 1
            local didBuy = false
            while need > 0 do
                local buy = math.min(stack, need)
                BuyMerchantItem(i, buy)
                need = need - buy
                didBuy = true
            end
            return didBuy
        end
    end

    return false
end

-- =========================================================
-- 六、事件订阅与配置刷新 | Events and Configuration Refresh
-- =========================================================
ExwindTools:RegisterEvent("MERCHANT_SHOW", EXWIND_MODULE_KEY, function()
    local boughtAnything = false

    -- 预设
    for id, data in pairs(EX_DB.Items) do
        if data.enabled and DoBuy(tonumber(id), tonumber(data.quantity) or 5) then
            boughtAnything = true
        end
    end

    -- 自定义
    for id, data in pairs(EX_DB.CustomItems) do
        if data.enabled and DoBuy(tonumber(id), tonumber(data.quantity) or 5) then
            boughtAnything = true
        end
    end

    if boughtAnything then
        print("|cff00ff00ExwindTools AutoBuy complete|r")
    end
end)

-- 报告模块加载完成
ExwindTools:ReportReady(EXWIND_MODULE_KEY)
