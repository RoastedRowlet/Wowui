-- =============================================================
-- [[ 技能就绪闪现 ]]
-- 法术或物品冷却结束时，在屏幕中央播放一次「图标放大 + 淡出」。
-- 冷却结束的判定来自原生 Cooldown 的 OnCooldownDone。
-- 法术冷却只把 C_Spell.GetSpellCooldownDuration 的 Duration 对象原样直传，
-- 不读取、比较或换算；物品冷却按用户 2026-10-05 给出的明确例外当作普通值
-- 读取（秘密值手册 §0.2 第 4 点：例外由用户给出，代理不得自行扩大）。
-- 动画按官方 Blizzard_CooldownViewer/PandemicAlertAnimation.xml 的
-- CooldownPandemicFXTemplate 写法：同一 order 内 Scale 与 Alpha 并行。
-- 显示为一次性缩放淡出特效：Core 显示手册未覆盖该形态（IconCollection 与
-- MaterialCollection 只有静态 SetItemVisualEffects，Alpha 序列只在
-- TextCollection），已核实 Core 源码无既有封装，按《动画与发光》的原生
-- AnimationGroup 生命周期自行持有。
-- =============================================================

-- =========================================================
-- 一、模块标识与依赖引用 | Module Identity and Dependencies
-- =========================================================
local ExwindTools = _G.ExwindTools
if not ExwindTools or not ExwindTools.UI then return end

local EXUI = ExwindTools.UI
local Grid = ExwindTools.Grid
local L = ExwindTools.L or setmetatable({}, { __index = function(_, key) return key end })
local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local C_Spell = _G.C_Spell
local C_Item = _G.C_Item
local C_Container = _G.C_Container
local C_DurationUtil = _G.C_DurationUtil
local GetTime = _G.GetTime
local MODULE_KEY = "ExTools.CooldownFlash"
local SPELL_LIST_RENDERER = MODULE_KEY .. ".SpellList"
local ITEM_LIST_RENDERER = MODULE_KEY .. ".ItemList"
local FALLBACK_ICON_FILE_ID = 134400
local MIN_REPLAY_INTERVAL = 0.5
local ICON_CROP = 0.08
local ApplyAppearance

ExwindTools:RegisterExternalModule({
    Key = MODULE_KEY,
    Name = L["技能就绪闪现"],
    Desc = L["法术或物品冷却结束时，在屏幕中央放大淡出一次图标。"],
    Category = 6,
})

-- =========================================================
-- 二、默认配置与配置访问 | Defaults and Configuration Access
-- =========================================================
-- spells／items 是 ID 字符串数组，按声明合同在 root 中完整声明。
ExwindTools:DeclareModuleSpecDefaults(MODULE_KEY, {
    root = {
        enabled = true,
        spells = {},
        items = {},
        size = 84,
        offsetX = 0,
        offsetY = 0,
        scaleFrom = 0.6,
        scaleTo = 2,
        duration = 0.8,
    },
})
local DB = ExwindTools:GetModuleDB(MODULE_KEY)

-- =========================================================
-- 五、业务状态与功能逻辑 | Business State and Logic — 法术与物品资料
-- =========================================================
local spellDisplayCache = {}
local itemDisplayCache = {}

local function ParseEntryID(value)
    local id = tonumber(value)
    if not id or id <= 0 or id % 1 ~= 0 then
        return nil
    end
    return id
end

local function GetSpellList()
    if type(DB.spells) ~= "table" then return {} end
    return DB.spells
end

local function GetItemList()
    if type(DB.items) ~= "table" then return {} end
    return DB.items
end

local function ListContains(list, id)
    if not id then return false end
    for _, value in ipairs(list) do
        if ParseEntryID(value) == id then return true end
    end
    return false
end

local function IsTrackedSpell(spellID)
    return ListContains(GetSpellList(), spellID)
end

local function IsTrackedItem(itemID)
    return ListContains(GetItemList(), itemID)
end

-- 取得法术名称与图标；未缓存时按官方流程请求一次，不自行推断失败。
local function GetSpellRecord(value)
    local spellID = ParseEntryID(value)
    if not spellID then return nil end

    local cached = spellDisplayCache[spellID]
    if not cached then
        cached = {}
        spellDisplayCache[spellID] = cached
    end

    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    if info then
        cached.name = info.name
        cached.iconID = info.iconID
        cached.requested = nil
        cached.completed = true
    elseif C_Spell and C_Spell.RequestLoadSpellData and not cached.requested and not cached.completed then
        local exists = not C_Spell.DoesSpellExist or C_Spell.DoesSpellExist(spellID) == true
        local isCached = C_Spell.IsSpellDataCached and C_Spell.IsSpellDataCached(spellID) == true
        if exists and not isCached then
            cached.requested = true
            C_Spell.RequestLoadSpellData(spellID)
        else
            cached.completed = true
        end
    end

    return cached
end

-- 物品名称与图标走 ItemID 版接口，缺资料时请求一次等 ITEM_DATA_LOAD_RESULT。
local function GetItemRecord(value)
    local itemID = ParseEntryID(value)
    if not itemID or not C_Item then return nil end

    local cached = itemDisplayCache[itemID]
    if not cached then
        cached = {}
        itemDisplayCache[itemID] = cached
    end

    if C_Item.GetItemIconByID then
        cached.iconID = C_Item.GetItemIconByID(itemID) or cached.iconID
    end
    local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
    if name then
        cached.name = name
        cached.requested = nil
        cached.completed = true
    elseif C_Item.RequestLoadItemDataByID and not cached.requested and not cached.completed then
        local isCached = C_Item.IsItemDataCachedByID and C_Item.IsItemDataCachedByID(itemID) == true
        if isCached then
            cached.completed = true
        else
            cached.requested = true
            C_Item.RequestLoadItemDataByID(itemID)
        end
    end

    return cached
end

local function BuildDisplayText(record, unknownText)
    local name = (record and record.name) or unknownText
    if record and record.iconID then
        return string.format("|T%s:20:20:0:0|t %s", tostring(record.iconID), name)
    end
    return name
end

local function GetSpellDisplayText(value)
    if not ParseEntryID(value) then return L["无效法术 ID"] end
    return BuildDisplayText(GetSpellRecord(value), L["未知法术"])
end

local function GetItemDisplayText(value)
    if not ParseEntryID(value) then return L["无效物品 ID"] end
    return BuildDisplayText(GetItemRecord(value), L["未知物品"])
end

local function GetSpellIconFileID(spellID)
    if spellID and C_Spell and C_Spell.GetSpellTexture then
        return C_Spell.GetSpellTexture(spellID)
    end
    return nil
end

local function GetItemIconFileID(itemID)
    if itemID and C_Item and C_Item.GetItemIconByID then
        return C_Item.GetItemIconByID(itemID)
    end
    return nil
end

-- 测试播放没有具体来源时的回退图标：先法术后物品，都没有才用问号。
local function GetFirstTrackedIconFileID()
    for _, value in ipairs(GetSpellList()) do
        local fileID = GetSpellIconFileID(ParseEntryID(value))
        if fileID then return fileID end
    end
    for _, value in ipairs(GetItemList()) do
        local fileID = GetItemIconFileID(ParseEntryID(value))
        if fileID then return fileID end
    end
    return nil
end

-- =========================================================
-- 三、GUI 声明 | GUI Declarations — 列表表格
-- =========================================================
local function ReleaseListControl(control)
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

local function ClearListRows(controls)
    for index = #controls.rows, 1, -1 do
        local record = controls.rows[index]
        if record.idControlIsEditBox then
            -- OnEditFocusLost 槽位上有 Core 的焦点画器，走 ClearControlScript
            -- 清槽位时一并丢掉安装记录，下一次借用才会重装画器。
            EXUI:ClearControlScript(record.idControl, "OnEditFocusLost")
            record.idControl:SetScript("OnEnterPressed", nil)
        end
        ReleaseListControl(record.action)
        ReleaseListControl(record.nameText)
        ReleaseListControl(record.idControl)
        controls.rows[index] = nil
    end
end

-- 法术表与物品表共用同一套行逻辑，只替换取列表、显示文字与提示文案。
local function CreateListFactory(spec)
    local list = { host = nil, ctx = nil }

    local function Rebuild(host, ctx)
        local controls = host and host[spec.controlsKey]
        if not controls then return end
        ctx:ReleaseTablePresentation()
        ClearListRows(controls)

        local addRecord = {
            idControl = EXUI:CreateEditBox(host, "", 1, 28, nil, { placeholder = spec.placeholder }),
            idControlIsEditBox = true,
            nameText = EXUI:CreateDescription(host, spec.hint, 1),
        }

        -- 添加按钮与输入框回车走同一条路径。
        local function AddFromInput()
            local id = ParseEntryID(addRecord.idControl:GetText())
            if not id then return end
            local entries = spec.GetList()
            entries[#entries + 1] = tostring(id)
            addRecord.idControl:SetText("")
            Rebuild(host, ctx)
            ctx:RequestReflow()
        end

        addRecord.idControl:SetScript("OnEnterPressed", function(self)
            -- 先交还焦点，再重建行；重建会释放这个输入框本身。
            self:ClearFocus()
            AddFromInput()
        end)
        addRecord.action = EXUI:CreateButton(host, 1, 28, L["添加"], AddFromInput,
            { variant = "primary", compact = true })
        controls.rows[#controls.rows + 1] = addRecord

        for index, value in ipairs(spec.GetList()) do
            local rowIndex = index
            local record = {}
            record.idControl = EXUI:CreateDescription(host, tostring(value), 1)
            record.nameText = EXUI:CreateDescription(host, spec.GetDisplayText(value), 1)
            record.action = EXUI:CreateButton(host, 1, 28, L["删除"], function()
                table.remove(spec.GetList(), rowIndex)
                Rebuild(host, ctx)
                ctx:RequestReflow()
            end, { variant = "danger", compact = true })
            controls.rows[#controls.rows + 1] = record
        end

        local presented = {}
        for index = 2, #controls.rows do
            local record = controls.rows[index]
            presented[#presented + 1] = {
                cells = {
                    { widget = record.idControl, type = "text" },
                    { widget = record.nameText, type = "text" },
                    { widget = record.action, type = "button" },
                },
            }
        end

        ctx:SetTableControls({
            add = {
                cells = {
                    { widget = addRecord.idControl, type = "input" },
                    { widget = addRecord.nameText, type = "text" },
                    { widget = addRecord.action, type = "button" },
                },
            },
            records = presented,
        })
    end

    if Grid and Grid.RegisterTableControls then
        Grid:RegisterTableControls(spec.rendererKey, {
            mount = function(host, ctx)
                list.host, list.ctx = host, ctx
                host[spec.controlsKey] = { rows = {} }
                Rebuild(host, ctx)
            end,
            update = function(host, ctx)
                list.host, list.ctx = host, ctx
                Rebuild(host, ctx)
            end,
            release = function(host)
                local controls = host[spec.controlsKey]
                if controls then ClearListRows(controls) end
                host[spec.controlsKey] = nil
                if list.host == host then
                    list.host, list.ctx = nil, nil
                end
            end,
        })
    end

    -- 资料异步返回后重画已挂载的那张表；没挂载时什么都不做。
    function list:Refresh()
        if self.host and self.ctx then Rebuild(self.host, self.ctx) end
    end

    return list
end

local spellList = CreateListFactory({
    rendererKey = SPELL_LIST_RENDERER,
    controlsKey = "_exCooldownFlashSpellList",
    placeholder = L["输入法术 ID"],
    hint = L["填入法术 ID 后按添加或回车"],
    GetList = GetSpellList,
    GetDisplayText = GetSpellDisplayText,
})

local itemList = CreateListFactory({
    rendererKey = ITEM_LIST_RENDERER,
    controlsKey = "_exCooldownFlashItemList",
    placeholder = L["输入物品 ID"],
    hint = L["填入物品 ID 后按添加或回车"],
    GetList = GetItemList,
    GetDisplayText = GetItemDisplayText,
})

local SPELL_LIST_COLUMNS = {
    { title = L["法术 ID"] },
    { title = L["法术"] },
    { title = L["操作"] },
}

local ITEM_LIST_COLUMNS = {
    { title = L["物品 ID"] },
    { title = L["物品"] },
    { title = L["操作"] },
}

-- =========================================================
-- 三、GUI 声明 | GUI Declarations — 页面声明
-- =========================================================
ExwindTools:RegisterModuleLayout(MODULE_KEY, {
    version = 1,
    sections = {
        {
            kind = "composite", id = "common", title = L["模块设置"],
            component = "modulecommonsettings", key = "moduleCommon",
            opts = {
                bindRoot = true,
                fields = { { path = "enabled", type = "checkbox", label = L["启用"] } },
            },
        },
        {
            kind = "table", id = "spells", title = L["监控法术"],
            description = L["列表中任一法术冷却结束时播放一次闪现。"],
            key = "spells", controlFactory = SPELL_LIST_RENDERER,
            columns = SPELL_LIST_COLUMNS, supportsAdd = true,
        },
        {
            kind = "table", id = "items", title = L["监控物品"],
            description = L["列表中任一物品冷却结束时播放一次闪现。"],
            key = "items", controlFactory = ITEM_LIST_RENDERER,
            columns = ITEM_LIST_COLUMNS, supportsAdd = true,
        },
        {
            kind = "settings", id = "test", title = L["测试"],
            items = {
                { key = "btn_test", type = "button", label = L["测试播放"] },
            },
        },
        {
            kind = "settings", id = "appearance", title = L["闪现外观"],
            items = {
                { key = "size", type = "slider", label = L["图标大小"], min = 32, max = 150, step = 2 },
                { key = "offsetX", type = "slider", label = L["水平偏移"], min = -800, max = 800, step = 1 },
                { key = "offsetY", type = "slider", label = L["垂直偏移"], min = -600, max = 600, step = 1 },
                { key = "scaleFrom", type = "slider", label = L["起始缩放"], min = 0.1, max = 3, step = 0.05 },
                { key = "scaleTo", type = "slider", label = L["结束缩放"], min = 0.1, max = 5, step = 0.05 },
                { key = "duration", type = "slider", label = L["动画时长"], min = 0.1, max = 3, step = 0.05 },
            },
        },
    },
})

-- 设置变更只重投影已经存在的宿主与动画参数；不在这里创建或播放。
EXUI:RegisterModuleValueController(MODULE_KEY, {
    RefreshActiveSurfaces = function()
        ApplyAppearance()
    end,
})

if not ExwindTools:IsModuleEnabled(MODULE_KEY) then return end

-- =========================================================
-- 四、显示、预览与编辑接入 | Display, Preview and Edit Integration
-- =========================================================
local lastPlayTime = 0
local displayHost, flashTexture, flashGroup, scaleAnim, alphaAnim

local function EnsureDisplay()
    if displayHost then return end

    displayHost = CreateFrame("Frame", nil, UIParent)
    displayHost:SetFrameStrata("HIGH")
    displayHost:EnableMouse(false)
    displayHost:Hide()

    flashTexture = EXUI:CreateVisualTexture(displayHost, _G.EXBASEFRAME)
    flashTexture:SetPoint("CENTER", displayHost, "CENTER", 0, 0)
    flashTexture:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)

    flashGroup = flashTexture:CreateAnimationGroup()
    scaleAnim = flashGroup:CreateAnimation("Scale")
    scaleAnim:SetOrder(1)
    scaleAnim:SetOrigin("CENTER", 0, 0)
    scaleAnim:SetSmoothing("OUT")
    alphaAnim = flashGroup:CreateAnimation("Alpha")
    alphaAnim:SetOrder(1)
    alphaAnim:SetSmoothing("OUT")
    flashGroup:SetScript("OnFinished", function()
        displayHost:Hide()
    end)

    ApplyAppearance()
end

ApplyAppearance = function()
    if not displayHost then return end

    local size = math.max(8, tonumber(DB.size) or 84)
    local seconds = math.max(0.1, tonumber(DB.duration) or 0.8)
    local scaleFrom = math.max(0.01, tonumber(DB.scaleFrom) or 0.6)
    local scaleTo = math.max(0.01, tonumber(DB.scaleTo) or 2)

    displayHost:SetSize(size, size)
    displayHost:ClearAllPoints()
    displayHost:SetPoint("CENTER", UIParent, "CENTER", tonumber(DB.offsetX) or 0, tonumber(DB.offsetY) or 0)
    flashTexture:SetSize(size, size)

    scaleAnim:SetDuration(seconds)
    scaleAnim:SetScaleFrom(scaleFrom, scaleFrom)
    scaleAnim:SetScaleTo(scaleTo, scaleTo)
    alphaAnim:SetDuration(seconds)
    alphaAnim:SetFromAlpha(1)
    alphaAnim:SetToAlpha(0)
end

-- fileID 由调用方按来源解析；nil 时回落到列表里第一个可用图标。
local function PlayFlash(fileID, force)
    if force ~= true and DB.enabled ~= true then return end

    local now = GetTime()
    if force ~= true and (now - lastPlayTime) < MIN_REPLAY_INTERVAL then return end
    lastPlayTime = now

    EnsureDisplay()
    flashGroup:Stop()
    ApplyAppearance()

    flashTexture:SetTexture(fileID or GetFirstTrackedIconFileID() or FALLBACK_ICON_FILE_ID)
    flashTexture:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    flashTexture:SetAlpha(1)
    displayHost:Show()
    flashGroup:Play()
end

-- =========================================================
-- 五、业务状态与功能逻辑 | Business State and Logic — 冷却监听
-- =========================================================
-- 每个被监控的 ID 一个隐藏 Cooldown：冷却结束通知的唯一来源是原生 OnCooldownDone。
local watcherHost
local spellWatchers = {}
local itemWatchers = {}
local itemDurations = {}

local function EnsureWatcherHost()
    if watcherHost then return watcherHost end
    watcherHost = CreateFrame("Frame", nil, UIParent)
    watcherHost:SetSize(1, 1)
    watcherHost:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    watcherHost:EnableMouse(false)
    watcherHost:SetAlpha(0)
    watcherHost:Show()
    return watcherHost
end

local function CreateWatcher(onDone)
    local watcher = CreateFrame("Cooldown", nil, EnsureWatcherHost(), "CooldownFrameTemplate")
    watcher:SetAllPoints(watcherHost)
    watcher:EnableMouse(false)
    watcher:SetDrawSwipe(false)
    watcher:SetDrawEdge(false)
    watcher:SetDrawBling(false)
    watcher:SetHideCountdownNumbers(true)
    watcher.noCooldownCount = true
    watcher.noOCC = true
    watcher:SetScript("OnCooldownDone", onDone)
    return watcher
end

local function EnsureSpellWatcher(spellID)
    local watcher = spellWatchers[spellID]
    if watcher then return watcher end
    watcher = CreateWatcher(function()
        if IsTrackedSpell(spellID) then PlayFlash(GetSpellIconFileID(spellID)) end
    end)
    spellWatchers[spellID] = watcher
    return watcher
end

local function EnsureItemWatcher(itemID)
    local watcher = itemWatchers[itemID]
    if watcher then return watcher end
    watcher = CreateWatcher(function()
        if IsTrackedItem(itemID) then PlayFlash(GetItemIconFileID(itemID)) end
    end)
    itemWatchers[itemID] = watcher
    return watcher
end

-- 物品冷却事件不带 payload，只能对列表逐个重设；起点沿用 API 给的 startTime，
-- 不以 GetTime 重置。物品冷却按用户给出的例外当普通值读取。
local function RefreshItemCooldowns()
    if DB.enabled ~= true then return end
    if not (C_Container and C_Container.GetItemCooldown and C_DurationUtil) then return end

    for _, value in ipairs(GetItemList()) do
        local itemID = ParseEntryID(value)
        if itemID then
            -- MayReturnNothing：整次可能没有返回。
            local startTime, durationSeconds, enable = C_Container.GetItemCooldown(itemID)
            if startTime and durationSeconds and enable and enable ~= 0
                and startTime > 0 and durationSeconds > 0 then
                local durationObject = itemDurations[itemID]
                if not durationObject then
                    durationObject = C_DurationUtil.CreateDuration()
                    itemDurations[itemID] = durationObject
                end
                durationObject:SetTimeFromStart(startTime, durationSeconds, 1)
                local watcher = EnsureItemWatcher(itemID)
                watcher:SetCooldownFromDurationObject(durationObject, true)
                watcher:Show()
            end
        end
    end
end

-- =========================================================
-- 六、事件订阅与配置刷新 | Events and Configuration Refresh
-- =========================================================
ExwindTools:RegisterEvent("SPELL_UPDATE_COOLDOWN", MODULE_KEY, function(_, spellID, baseSpellID)
    if DB.enabled ~= true then return end
    if not (C_Spell and C_Spell.GetSpellCooldownDuration) then return end

    local tracked = (IsTrackedSpell(spellID) and spellID)
        or (IsTrackedSpell(baseSpellID) and baseSpellID)
        or nil
    if not tracked then return end

    -- MayReturnNothing：整次可能没有返回；拿到的 Duration 只原样直传。
    local duration = C_Spell.GetSpellCooldownDuration(tracked, true)
    if not duration then return end

    local watcher = EnsureSpellWatcher(tracked)
    watcher:SetCooldownFromDurationObject(duration, true)
    watcher:Show()
end)

-- 背包与动作条两个冷却事件都不带 payload，统一走同一次全量重设。
ExwindTools:RegisterEvent("BAG_UPDATE_COOLDOWN", MODULE_KEY, RefreshItemCooldowns)
ExwindTools:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN", MODULE_KEY, RefreshItemCooldowns)

-- Grid 只发布纯点击状态。
ExwindTools:WatchState(MODULE_KEY .. ".ButtonClicked", MODULE_KEY, function(click)
    if click and click.key == "btn_test" then
        PlayFlash(nil, true)
    end
end)

-- 法术资料异步返回后补上列表里的名称与图标。
ExwindTools:RegisterEvent("SPELL_DATA_LOAD_RESULT", MODULE_KEY, function(_, spellID, success)
    spellID = tonumber(spellID)
    local cached = spellID and spellDisplayCache[spellID]
    if not cached then return end
    cached.requested = nil
    cached.completed = true
    if success == true and C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if info then
            cached.name = info.name
            cached.iconID = info.iconID
        end
    end
    spellList:Refresh()
end)

ExwindTools:RegisterEvent("ITEM_DATA_LOAD_RESULT", MODULE_KEY, function(_, itemID, success)
    itemID = tonumber(itemID)
    local cached = itemID and itemDisplayCache[itemID]
    if not cached then return end
    cached.requested = nil
    cached.completed = true
    if success == true and C_Item then
        if C_Item.GetItemNameByID then cached.name = C_Item.GetItemNameByID(itemID) or cached.name end
        if C_Item.GetItemIconByID then cached.iconID = C_Item.GetItemIconByID(itemID) or cached.iconID end
    end
    itemList:Refresh()
end)

-- =========================================================
-- 七、初始化与启动 | Initialization and Startup
-- =========================================================
ExwindTools:ReportReady(MODULE_KEY)
