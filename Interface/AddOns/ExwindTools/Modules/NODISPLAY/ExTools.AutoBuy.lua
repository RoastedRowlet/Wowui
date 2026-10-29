-- [[ 自动购买 ]]
-- { Key = "ExTools.AutoBuy", Name = "自动购买", Desc = "在商人处自动购买预设或自定义的物品（如钥石地图、消耗品等）。", Category = 4 },

-- =========================================================
-- 一、模块标识与依赖引用 | Module Identity and Dependencies
-- =========================================================
local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI
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

local presetRecords = {}
for _, category in ipairs({ "food", "key", "map" }) do
    if category == "food" or ExwindTools.IsBeta then
        for _, item in ipairs(PRESET_ITEMS) do
            if item.cat == category then
                if not EX_DB.Items[item.id] then
                    EX_DB.Items[item.id] = { enabled = true, quantity = item.buy }
                end
                presetRecords[#presetRecords + 1] = { key = item.id, id = item.id, parentKey = "Items", data = EX_DB.Items[item.id] }
                ItemTextCell(item.id)
            end
        end
    end
end

local settingsSession
local function RefreshSettings()
    if settingsSession and settingsSession.alive then settingsSession:Refresh() end
end

local function Cell(id, child)
    return { id = id, kind = "cell", children = { child } }
end

local function BuildV2Declaration()
    local rows = {}
    for _, prefix in ipairs({ "custom", "preset" }) do
        rows[#rows + 1] = { id = prefix .. ".rows", kind = "repeat", source = prefix, template = {
            id = prefix .. ".row", kind = "row", children = {
                Cell(prefix .. ".enabled", { id = prefix .. "_enabled", kind = "control", controlType = "checkbox", ref = "itemEnabled" }),
                Cell(prefix .. ".item", { id = prefix .. ".item.identity", kind = "text", textSource = "itemIdentity" }),
                Cell(prefix .. ".quantity", { id = prefix .. "_quantity", kind = "control", controlType = "input", ref = "itemQuantity" }),
            },
        } }
    end
    return { version = 2, cards = {
        { id = "general", kind = "card", title = L["通用设置"], children = {
            { id = "general.add", kind = "setting", label = L["物品 ID"],
                description = L["当打开商人界面时，自动购买背包中缺少的物品 (自动补齐到设置数量)"], children = {
                { id = "addID", kind = "control", controlType = "input", path = "addID" },
            } },
            { id = "general.table", kind = "table", columns = {
                { title = L["启用"] }, { title = L["物品"] }, { title = L["数量"] },
            }, addAction = { id = "addItem", text = L["添加"], clickKey = "addItem" },
            rowActions = { { id = "custom_delete", text = L["删除"], action = "deleteItem",
                enabled = "customItem", presentation = "danger" } }, children = rows },
        } },
    } }
end

local function CreateV2Owner()
    local owner = { binding = { moduleKey = EXWIND_MODULE_KEY, config = EX_DB },
        controls = {}, texts = {}, sources = {}, actions = {}, predicates = {} }
    function owner:AttachSession(session) settingsSession = session end
    local customRecords = {}
    owner.sources.custom = function()
        local records = {}
        for key, data in pairs(EX_DB.CustomItems) do
            local record = customRecords[key]
            if not record or record.data ~= data then
                record = { key = key, id = tonumber(key), parentKey = "CustomItems", data = data }
                customRecords[key] = record
            end
            records[#records + 1] = record
        end
        table.sort(records, function(a, b)
            if a.id == b.id then return type(a.key) < type(b.key) end
            return a.id < b.id
        end)
        return records
    end
    owner.sources.preset = function()
        for index, record in ipairs(presetRecords) do
            local data = EX_DB.Items[record.key]
            if record.data ~= data then
                presetRecords[index] = { key = record.key, id = record.id, parentKey = "Items", data = data }
            end
        end
        return presetRecords
    end
    local function ItemBinding(context, field)
        local record = context.scope.item
        -- 绑定原记录本体，保留物品 ID 的原始数字／字符串键；完整路径只用于通知。
        local binding = EXUI:CreateSettingsV2Binding(EXWIND_MODULE_KEY, EX_DB[record.parentKey][record.key], field)
        binding.path = record.parentKey .. "." .. record.key .. "." .. field
        local write = binding.Write
        function binding:Write(value, phase)
            if not context:IsCurrent() then return false end
            return write(self, value, phase)
        end
        return binding
    end
    owner.controls.itemEnabled = EXUI:CreateSettingsV2Control({ controlType = "checkbox", label = "" },
        function(context) return ItemBinding(context, "enabled") end)
    owner.controls.itemQuantity = EXUI:CreateSettingsV2Control({ controlType = "input" }, function(context)
        local binding = ItemBinding(context, "quantity")
        local read, write = binding.Read, binding.Write
        function binding:Read() return read(self) or 1 end
        function binding:Write(value, phase)
            return write(self, tonumber(value) or 1, phase)
        end
        return binding
    end)
    local mountQuantity = owner.controls.itemQuantity.mount
    owner.controls.itemQuantity.mount = function(host, context)
        local widget = mountQuantity(host, context)
        widget:SetJustifyH("CENTER")
        widget:SetNumeric(true)
        return widget
    end
    owner.texts.itemIdentity = function(scope)
        local cell = ItemTextCell(scope.item.id)
        return "|T" .. cell.icon .. ":0|t " .. cell.text
    end
    owner.predicates.customItem = function(scope) return scope.item.parentKey == "CustomItems" end
    owner.actions.deleteItem = function(context)
        local key = context.scope.item.key
        ExwindTools:UpdateState(EXWIND_MODULE_KEY .. ".ItemConfigDelete", { key = key })
    end
    return owner
end

EXUI:RegisterModuleSettingsPageV2(EXWIND_MODULE_KEY, BuildV2Declaration(), CreateV2Owner)

ExwindTools:RegisterEvent("GET_ITEM_INFO_RECEIVED", EXWIND_MODULE_KEY, function(_, itemID, success)
    if not pendingItemInfo[itemID] then return end
    pendingItemInfo[itemID] = nil
    if not success then return end
    RefreshSettings()
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
            RefreshSettings()
        end
    end
end)

-- 2. 处理 ItemConfig 组件上报的删除事件
ExwindTools:WatchState(EXWIND_MODULE_KEY .. ".ItemConfigDelete", EXWIND_MODULE_KEY, function(data)
    local id = data.key
    if id and EX_DB.CustomItems[id] then
        EX_DB.CustomItems[id] = nil
        RefreshSettings()
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
