local addonName, addonTable = ...
local ExwindTools = addonTable
_G.ExwindTools = ExwindTools

-- 12S2 hard cut: the three addons now own three new SavedVariables names.
-- No migration is allowed.  Clear the legacy globals in memory as a second
-- guarantee; because their TOC declarations are also removed, the next saved
-- variables flush removes the old payload from disk.
_G.ExwindToolsDB = nil -- EXWIND_LEGACY_DB_PURGE
_G.ExBossDB = nil      -- EXWIND_LEGACY_DB_PURGE
local legacyDBPurge = CreateFrame("Frame")
legacyDBPurge:RegisterEvent("ADDON_LOADED")
legacyDBPurge:SetScript("OnEvent", function(_, _, loadedAddon)
    local name = tostring(loadedAddon or ""):lower()
    if name == "exwindtools" then
        _G.ExwindToolsDB = nil -- EXWIND_LEGACY_DB_PURGE
    elseif name == "exboss" then
        -- ExBoss' old SavedVariables file is loaded only immediately before
        -- ExBoss code, which is later than Core. Purge it at that exact event.
        _G.ExBossDB = nil -- EXWIND_LEGACY_DB_PURGE
    end
end)

-- 把 Locale 代理接入 addonTable（ExwindLocale 由 Locale/Init.lua 提前初始化）
ExwindTools.L = _G.ExwindLocale and _G.ExwindLocale.GetProxy() or
    setmetatable({}, { __index = function(_, k) return k end })

local L = ExwindTools.L

--=======================================================================
--========================== 基础属性 ===================================
--=======================================================================
ExwindTools.name = addonName
-- [Core] 版本信息 (从 ExwindTools_Metadata.lua 读取)
local meta = _G.ExwindTools_MetaData or { version = "DEV-Build", gridEngineVersion = "DEV" }
ExwindTools.VERSION = meta.version
ExwindTools.GridEngineVersion = meta.gridEngineVersion

--=======================================================================
--========================== 全局字体准则 ===============================
--=======================================================================
-- [Core] 建立最高优先级的原生字体指针
local nativePath, nativeSize, nativeFlags = _G.GameFontHighlight:GetFont()
ExwindTools.MAIN_FONT = nativePath or STANDARD_TEXT_FONT

-- 针对 enUS 客户端的解决方案：中文玩家在英文客户端运行时，native font 不含 CJK 字形，
-- 需要从 LSM 查找 AR 字体覆盖 MAIN_FONT 以支持 HUD SetFont 渲染。
-- zhCN/zhTW：native font 本身就是 AR 字体，无需覆盖。
-- deDE/frFR/esES 等拉丁语客户端：native font 含 ä/ö/ü/ß 等字形，覆盖为 CJK 字体会导致乱码，跳过。
local currentLocale = GetLocale()
if currentLocale == "enUS" then
    local LSM = LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local cjkFonts = { "AR ZhongkaiGBK Medium", "AR CrystalzcuheiGBK Demibold" }
        for _, name in ipairs(cjkFonts) do
            local path = LSM:Fetch("font", name)
            if path and path ~= "" then
                ExwindTools.MAIN_FONT = path
                break
            end
        end
    end
end

ExwindTools.MAIN_FONT_SIZE = 16
ExwindTools.MAIN_FONT_OUTLINE = "OUTLINE"

--=======================================================================
--========================== 环境判断 ===================================
--=======================================================================
local version, build, date, tocversion = GetBuildInfo()
local isPTR = IsPublicTestClient and IsPublicTestClient()
local isBeta = IsBetaBuild and IsBetaBuild()
local realmID = GetRealmID and GetRealmID() or 0
local isBetaRealm = (realmID == 4608)

-- 只要是测试服环境（PTR / Beta / 指定测试服务器），都认为是 Beta 环境
ExwindTools.IsBeta = isBeta or isPTR or isBetaRealm


--=======================================================================
--========================== 分类定义 ===================================
--=======================================================================
ExwindTools.Cate = {
    [1] = L["工具类"],
    [2] = L["大秘境 (资讯)"],
    [3] = L["大秘境 (战斗)"],
    [4] = L["职业 (通用)"],
    [5] = "PTR/BETA",
    [6] = L["Class"],
}
--如果非beta服务器 抽掉分类4
if not ExwindTools.IsBeta then
    ExwindTools.Cate[5] = nil
end

--=======================================================================
--========================== 模块清单 ===================================
--=======================================================================
-- ⚠️ 警告：此 ModuleList 被多个插件共享
--  它是 Tools 左侧路由、模块管理与模块元数据的唯一真源。
--  内置模块在此显式登记；外置插件只能通过下方 RegisterExternalModule
--  入口注册一次，不能直接写入或覆盖此表。
ExwindTools.ModuleList = {
    ----------------------------------------------------------------------------------------------------------
    ---------------------------------------------工具类 (1)---------------------------------------------------
    ----------------------------------------------------------------------------------------------------------
    { Key = "ExTools.MiniTools", Name = L["常用功能设置"], Desc = L["常用功能合集 (自动卖垃圾/日志/删除确认等)。"], Category = 1 },
    { Key = "ExTools.CombatAlert", Name = L["进出战斗提示"], Desc = L["进入或离开战斗时显示提示文字。"], Category = 1 },
    { Key = "ExTools.PlayerPosition", Name = L["玩家角色定位"], Desc = L["在屏幕中心显示标记，支持超出距离变色"], Category = 1 },

    { Key = "ExTools.ChatChannelBar", Name = L["聊天频道切换"], Desc = L["快速切换聊天频道的工具栏"], Category = 1 },
    { Key = "ExTools.AutoBuy", Name = L["自动购买"], Desc = L["自动购买指定物品。"], Category = 1 },
    { Key = "ExTools.GossipID", Name = L["自动对话"], Desc = L["显示对话 ID，并支持加入自动对话列表。"], Category = 1, },
    { Key = "ExTools.CombatMobDebuffGrid", Name = L["周围怪物DEBUFF监控"], Desc = L["以格子显示周围进入战斗的敌对怪物；玩家或宠物施放的指定 Debuff 存在时显示红色。"], Category = 1 },
    -- { Key = "ExTools.MicroMenu", Name = L["微型选单"], Desc = L["顶端微型选单：中间显示时间，左右各有可配置的面板快捷图标。"], Category = 1 },
    { Key = "ExTools.RaidMarkerPanel", Name = L["团队标记面板"], Desc = L["目标标记 + 地面光柱的快捷操作面板。"], Category = 1 },

    ----------------------------------------------------------------------------------------------------------
    ---------------------------------------------大秘境资讯 (2)------------------------------------------------
    ----------------------------------------------------------------------------------------------------------
    { Key = "ExM+Info.MDTIconHook", Name = L["MDT 图标替换"], Desc = L["将 MDT 地图中怪物头像替换为法术图标。"], Category = 2 },
    { Key = "ExM+Info.MythicIcon", Name = L["大米分数/点击传送"], Desc = L["大秘境图标/分数/点击传送等增强。"], Category = 2 },
    { Key = "ExM+Info.TeleMsg", Name = L["大米传送喊话"], Desc = L["大秘境传送相关聊天喊话/提示。"], Category = 2 },
    { Key = "ExM+Info.SpellInfo", Name = L["大米法术查询"], Desc = L["法术信息查询与提示增强。"], Category = 2, HideCfg = true },
    { Key = "ExM+Info.Tooltip", Name = L["大米最佳记录(鼠标提示)"], Desc = L["大秘境相关 Tooltip/交互增强。"], Category = 2, HideCfg = true },
    { Key = "ExM+Info.RunHistory", Name = L["大米赛季记录"], Desc = L["记录/展示大秘境赛季历史数据。"], Category = 2, HideCfg = true },
    { Key = "ExM+InfoMythicFrame", Name = L["大秘境统计面板"], Desc = L["大秘境统计面板与展示。"], Category = 2, HideCfg = true },
    { Key = "ExM+InfoSpellData", Name = L["法术数据 (内部)"], Desc = L["内部数据/法术资料库。"], Category = 2, HideCfg = true },
    { Key = "ExM+.MythicDamage", Name = L["大秘境伤害计算"], Desc = L["独立UI，根据层数计算法术实际伤害。"], Category = 2 },
    { Key = "ExTools.PveInfoPanel", Name = L["PVE 扩展面板"], Desc = L["在副本查找器侧边显示额外信息挂架。"], Category = 2, },
    { Key = "ExTools.PveKeystoneInfo", Name = L["大米队友钥石"], Desc = L["在 PVEFrame 上显示玩家与队友钥石信息。"], Category = 2, },

    ----------------------------------------------------------------------------------------------------------
    ---------------------------------------------大秘境辅助 (3)------------------------------------------------
    ----------------------------------------------------------------------------------------------------------
    { Key = "ExClass.FocusCast", Name = L["焦点施法提示"], Desc = L["仅监控焦点施法，支持施法条与音效独立提示。"], Category = 3 },
    { Key = "ExTools.BattleResurrection", Name = L["战斗复活"], Desc = L["显示战斗复活的可用次数与恢复计时。"], Category = 3 },
    { Key = "ExTools.PlayerShield", Name = L["玩家护盾量"], Desc = L["在屏幕上显示玩家当前总护盾量"], Category = 3 },
    { Key = "ExTools.PlayerHealAbsorb", Name = L["玩家治疗吸收盾"], Desc = L["在屏幕上显示玩家当前总治疗吸收量。"], Category = 3 },
    { Key = "ExTools.CombatTimer", Name = L["战斗时间计时器"], Desc = L["显示本次战斗已持续的时间。"], Category = 3 },

    ----------------------------------------------------------------------------------------------------------
    ---------------------------------------------职业 (通用) (4)----------------------------------------------
    ----------------------------------------------------------------------------------------------------------
    { Key = "ExTools.SpellQueue", Name = L["全职业延迟容限"], Desc = L["根据当前专精自动调整输入延迟容限。"], Category = 4 },
    { Key = "ExClass.SpellEffectAlpha", Name = L["法术触发透明度"], Desc = L["根据当前专精自动调整法术触发透明度。"], Category = 4 },
    { Key = "ExTools.PlayerStats", Name = L["玩家属性监控"], Desc = L["采集并显示玩家各项战斗属性数据。"], Category = 4 },
    { Key = "ExTools.YYSound", Name = L["嗜血音效"], Desc = L["队友开启嗜血时播放音效 功能测试中"], Category = 4 },
    { Key = "ExTools.CastSequence", Name = L["施法序列"], Desc = L["实时显示你的施法序列，"], Category = 4 },
    { Key = "ExClass.RangeCheck", Name = L["距离监视"], Desc = L["实时显示目标距离范围。"], Category = 4 },

    ----------------------------------------------------------------------------------------------------------
    ---------------------------------------------职业  (6)----------------------------------------------
    ----------------------------------------------------------------------------------------------------------
    { Key = "ExClass.NoMoveSkillAlert", Name = L["位移技能CD提示"], Desc = L["当位移技能冷却中时提示。"], Category = 6 },
    { Key = "ExClass.BrewmasterStagger", Name = L["酒仙酒池监控"], Desc = L["显示酒仙武僧的酒池百分比，并支持独立满条上限与阈值变色。"], Category = 6 },
    { Key = "ExTools.TransformTimer", Name = L["噬灭变身计时"], Desc = L["玩家施放指定变身法术后，在屏幕显示持续秒数。"], Category = 6 },
    ----------------------------------------------------------------------------------------------------------
    ---------------------------------------------PTR/BETA (5)-------------------------------------------------
    ----------------------------------------------------------------------------------------------------------
    { Key = "ExPTR.MiniTools", Name = L["PTR工具箱"], Desc = L["汇集测试服专用的便捷功能"], Category = 5, BlockBeta = true },
    { Key = "ExPTR.SetKey", Name = L["快速设置钥石 (PTR)"], Desc = L["PTR 用：快速制作/设置钥石。"], Category = 5, BlockBeta = true, },
}

--如果非beta服务器 抽掉BlockBeta

if not ExwindTools.IsBeta then
    local i = 1
    while i <= #ExwindTools.ModuleList do
        if ExwindTools.ModuleList[i].BlockBeta then
            table.remove(ExwindTools.ModuleList, i)
        else
            i = i + 1
        end
    end
end

-- Key -> Index 映射
ExwindTools.ModuleIndexByKey = {}
for i, meta in ipairs(ExwindTools.ModuleList) do
    ExwindTools.ModuleIndexByKey[meta.Key] = i
end

function ExwindTools:GetModuleMeta(moduleKey)
    if type(moduleKey) ~= "string" or moduleKey == "" then return nil end
    local index = self.ModuleIndexByKey[moduleKey]
    return index and self.ModuleList[index] or nil
end

--=======================================================================
--========================== 数据库初始化 ===============================
--=======================================================================
_G.EXCORE12S2 = _G.EXCORE12S2 or {}
local db = _G.EXCORE12S2

db.DBVersion = db.DBVersion or 1
db.ModuleDB = db.ModuleDB or {}
db.Minimap = db.Minimap or { hide = false }
db.Locale = db.Locale or { mode = "AUTO" }

-- ExwindTools' SavedVariables are not loaded yet while its required Core is
-- executing. Keep the catalog in a transient table until ExwindTools registers
-- EXTOOLS12S2 from its first file; never persist Tools module data in Core.
local moduleCatalogDB = { DBVersion = 1, ModuleDB = {}, LoadByKey = {}, Load = {}, LoadKeys = {} }
local moduleDBStorages = { CORE = db }
local moduleDBOwnerByKey = {}
local moduleDBOwnerPrefixes = {}
local activeModuleDBOwner = "CORE"
local toolsCatalogOwner = nil

local function NormalizeLocaleMode(mode)
    local value = tostring(mode or ""):gsub("%s+", "")
    if value == "zhCN" or value == "zhTW" or value == "enUS" then
        return value
    end
    return "AUTO"
end

db.Locale.mode = NormalizeLocaleMode(db.Locale.mode)

-- 同步模块配置
local validKeys = {}
for i, meta in ipairs(ExwindTools.ModuleList) do
    local key = meta.Key
    validKeys[key] = true
    moduleCatalogDB.LoadKeys[i] = key
    if moduleCatalogDB.LoadByKey[key] == nil then moduleCatalogDB.LoadByKey[key] = (meta.DefaultEnabled ~= false) end
    moduleCatalogDB.Load[i] = moduleCatalogDB.LoadByKey[key]
end
for k in pairs(moduleCatalogDB.LoadByKey) do
    if not validKeys[k] then moduleCatalogDB.LoadByKey[k] = nil end
end

ExwindTools.DB = moduleCatalogDB

function ExwindTools:GetLocaleMode()
    db.Locale = db.Locale or { mode = "AUTO" }
    db.Locale.mode = NormalizeLocaleMode(db.Locale.mode)
    return db.Locale.mode
end

function ExwindTools:GetEffectiveLocale(mode)
    local localeAPI = _G.ExwindLocale
    local localeMode = NormalizeLocaleMode(mode or self:GetLocaleMode())
    if localeAPI and localeAPI.ResolveLocale then
        return localeAPI.ResolveLocale(localeMode)
    end
    if localeMode == "AUTO" then
        return GetLocale()
    end
    return localeMode
end

function ExwindTools:SetLocaleMode(mode)
    db.Locale = db.Locale or { mode = "AUTO" }
    db.Locale.mode = NormalizeLocaleMode(mode)

    local localeAPI = _G.ExwindLocale
    if localeAPI and localeAPI.SetLocaleMode then
        localeAPI.SetLocaleMode(db.Locale.mode)
    elseif localeAPI and localeAPI.SetCurrentLocale then
        localeAPI.SetCurrentLocale(self:GetEffectiveLocale(db.Locale.mode))
    end

    return db.Locale.mode
end

local function ApplyCoreCVars()
    local ok = pcall(function()
        if _G.C_CVar and _G.C_CVar.SetCVar then
            _G.C_CVar.SetCVar("Sound_NumChannels", "128")
        elseif _G.SetCVar then
            _G.SetCVar("Sound_NumChannels", "128")
        end
    end)
    return ok
end

ApplyCoreCVars()

local function SyncModuleRegistry()
    wipe(ExwindTools.ModuleIndexByKey)
    wipe(ExwindTools.DB.Load)
    wipe(ExwindTools.DB.LoadKeys)

    local validKeys = {}
    for i, meta in ipairs(ExwindTools.ModuleList) do
        local key = meta.Key
        validKeys[key] = true
        ExwindTools.ModuleIndexByKey[key] = i
        ExwindTools.DB.LoadKeys[i] = key
        if ExwindTools.DB.LoadByKey[key] == nil then
            ExwindTools.DB.LoadByKey[key] = (meta.DefaultEnabled ~= false)
        end
        ExwindTools.DB.Load[i] = ExwindTools.DB.LoadByKey[key]
    end

    for k in pairs(ExwindTools.DB.LoadByKey) do
        if not validKeys[k] then
            ExwindTools.DB.LoadByKey[k] = nil
        end
    end
end

-- 外置插件的源码仍归各自 AddOn 所有；这里仅把已经加载的模块资料接入
-- Tools 的既有导航、模块开关和设置页路由。禁止外置代码直接改 ModuleList。
function ExwindTools:RegisterExternalModule(meta)
    if type(meta) ~= "table" then
        error("RegisterExternalModule: meta must be table", 2)
    end

    local key = meta.Key
    if type(key) ~= "string" or key == "" then
        error("RegisterExternalModule: Key must be non-empty string", 2)
    end
    if type(meta.Name) ~= "string" or meta.Name == "" then
        error("RegisterExternalModule: Name must be non-empty string", 2)
    end
    if self.ModuleIndexByKey[key] then
        error("RegisterExternalModule: duplicate module key " .. key, 2)
    end
    if not toolsCatalogOwner then
        error("RegisterExternalModule: ExwindTools storage is not registered", 2)
    end

    local entry = {
        Key = key,
        Name = meta.Name,
        Desc = type(meta.Desc) == "string" and meta.Desc or "",
        Category = type(meta.Category) == "number" and meta.Category or 1,
        DefaultEnabled = meta.DefaultEnabled,
        HideCfg = meta.HideCfg == true,
    }

    self.ModuleList[#self.ModuleList + 1] = entry
    SyncModuleRegistry()
    return entry
end

-- Addons register their own already-loaded SavedVariables table from their
-- first Lua file. Declarations/GetModuleDB bind each moduleKey to that owner,
-- so later runtime calls never depend on whichever addon happened to load last.
function ExwindTools:RegisterAddonModuleStorage(owner, storage, ownsToolsCatalog, prefixes)
    if type(owner) ~= "string" or owner == "" or type(storage) ~= "table" then
        error("RegisterAddonModuleStorage requires owner and storage table", 2)
    end
    storage.ModuleDB = type(storage.ModuleDB) == "table" and storage.ModuleDB or {}
    moduleDBStorages[owner] = storage
    activeModuleDBOwner = owner
    for _, prefix in ipairs(type(prefixes) == "table" and prefixes or {}) do
        if type(prefix) == "string" and prefix ~= "" then
            moduleDBOwnerPrefixes[#moduleDBOwnerPrefixes + 1] = { prefix = prefix, owner = owner }
        end
    end
    if ownsToolsCatalog == true then
        toolsCatalogOwner = owner
        storage.DBVersion = storage.DBVersion or 1
        storage.LoadByKey = type(storage.LoadByKey) == "table" and storage.LoadByKey or {}
        storage.Load = {}
        storage.LoadKeys = {}
        self.DB = storage
        SyncModuleRegistry()
    end
    return storage
end

function ExwindTools:ResetAddonModuleStorage(owner)
    local storage = moduleDBStorages[owner]
    if type(storage) ~= "table" then return false end
    wipe(storage)
    storage.ModuleDB = {}
    if owner == toolsCatalogOwner then
        storage.DBVersion = 1
        storage.LoadByKey, storage.Load, storage.LoadKeys = {}, {}, {}
        self.DB = storage
        SyncModuleRegistry()
    end
    return true
end

local function ResolveModuleDBOwner(moduleKey)
    local owner = moduleDBOwnerByKey[moduleKey]
    if owner then return owner end
    local bestLength = -1
    for _, rule in ipairs(moduleDBOwnerPrefixes) do
        if moduleKey:sub(1, #rule.prefix) == rule.prefix and #rule.prefix > bestLength then
            owner, bestLength = rule.owner, #rule.prefix
        end
    end
    return owner or activeModuleDBOwner
end

local function BindModuleDBOwner(moduleKey)
    local owner = ResolveModuleDBOwner(moduleKey)
    if not moduleDBStorages[owner] then
        error("module DB owner is not registered: " .. tostring(owner), 3)
    end
    moduleDBOwnerByKey[moduleKey] = owner
    return owner
end

function ExwindTools:GetModuleDBStorage(moduleKey)
    if type(moduleKey) ~= "string" or moduleKey == "" then return nil end
    local owner = moduleDBOwnerByKey[moduleKey] or BindModuleDBOwner(moduleKey)
    return moduleDBStorages[owner], owner
end

--=======================================================================
--========================== DEBUG 模式 =================================
--=======================================================================
ExwindTools.DebugMode = false

function EXDebug(fmt, ...)
    if not ExwindTools.DebugMode then return end
    local msg = select("#", ...) > 0 and string.format(fmt, ...) or fmt
    print(string.format("|cffff9900[EX-DEBUG]|r %s", msg))
end

_G.EXDebug = EXDebug

--=======================================================================
--========================== 模块状态报告 ===============================
--=======================================================================
ExwindTools.ModuleStatus = {}
ExwindTools.RegisteredLayouts = {}
-- 模块默认值声明是源码唯一真源：模块作者可直接粘贴 Grid 导出的 EX_DEFAULTS。
-- 它只在首次取得 ModuleDB 时编译为运行时扁平结构；运行时不存在第二份映射或转发。
ExwindTools.ModuleDefaultDeclarations = {}

function ExwindTools:ReportReady(moduleKey)
    self.ModuleStatus[moduleKey] = "ready"
end

--=======================================================================
--========================== 错误日志收集 ===============================
--=======================================================================
ExwindTools.ErrorLog = {}
local MAX_ERROR_LOG = 20

function ExwindTools:LogError(source, message)
    local entry = { time = _G.date("%H:%M:%S"), source = source, message = tostring(message) }
    table.insert(self.ErrorLog, 1, entry)
    while #self.ErrorLog > MAX_ERROR_LOG do table.remove(self.ErrorLog) end
end

--=======================================================================
--========================== 依赖库检测 =================================
--=======================================================================
ExwindTools.LibStatus = {}

local function CheckLibs()
    local libs = {
        { name = "LibStub",  check = function() return _G.LibStub ~= nil end },
        {
            name = "CallbackHandler-1.0",
            check = function()
                return LibStub and LibStub:GetLibrary("CallbackHandler-1.0", true) ~= nil
            end
        },
        {
            name = "LibSharedMedia-3.0",
            check = function()
                return LibStub and LibStub:GetLibrary("LibSharedMedia-3.0", true) ~= nil
            end
        },
        { name = "LibAsync", check = function() return LibStub and LibStub:GetLibrary("LibAsync", true) ~= nil end },
        {
            name = "LibCustomGlow-1.0",
            check = function()
                return LibStub and
                    LibStub:GetLibrary("LibCustomGlow-1.0", true) ~= nil
            end
        },
        {
            name = "LibDBIcon-1.0",
            check = function()
                return LibStub and
                    LibStub:GetLibrary("LibDBIcon-1.0", true) ~= nil
            end
        },
        {
            name = "LibDataBroker-1.1",
            check = function()
                return LibStub and
                    LibStub:GetLibrary("LibDataBroker-1.1", true) ~= nil
            end
        },
        { name = "LibDeflate", check = function() return LibStub and LibStub:GetLibrary("LibDeflate", true) ~= nil end },
        {
            name = "LibSerialize",
            check = function()
                return LibStub and
                    LibStub:GetLibrary("LibSerialize", true) ~= nil
            end
        },
    }
    for _, lib in ipairs(libs) do
        local ok, result = pcall(lib.check)
        ExwindTools.LibStatus[lib.name] = (ok and result) and true or false
    end
end
CheckLibs()
C_Timer.After(3, CheckLibs)

--=======================================================================
--========================== 环境信息采集 ===============================
--=======================================================================
function ExwindTools:GetEnvironmentInfo()
    local version, build, buildDate = GetBuildInfo()
    local isPTR = (IsPublicTestClient and IsPublicTestClient()) and L["是"] or L["否"]
    local isBeta = (IsBetaBuild and IsBetaBuild()) and L["是"] or L["否"]
    local realmID = GetRealmID and GetRealmID() or 0
    local isBetaRealm = (realmID == 4608) and L["是"] or L["否"]
    local isBetaEnv = self.IsBeta and L["是"] or L["否"]
    local platform = IsWindowsClient() and "Windows" or (IsMacClient() and "Mac" or "Unknown")
    local arch = Is64BitClient() and "64-bit" or "32-bit"
    local gameLocale = GetLocale()
    local regionID = GetCurrentRegion()
    local regionMap = { [1] = "US", [2] = "KR", [3] = "EU", [4] = "TW", [5] = "CN", [90] = "BETA" }

    return {
        addonVersion = self.VERSION,
        dbVersion = db.DBVersion,
        gameVersion = version,
        gameBuild = build,
        buildDate = buildDate,
        isPTR = isPTR,
        isBeta = isBeta,
        realmID = realmID,
        isBetaRealm = isBetaRealm,
        isBetaEnv = isBetaEnv,
        isElvUI = C_AddOns.IsAddOnLoaded("ElvUI") and L["是"] or L["否"],
        platform = platform,
        arch = arch,
        locale = gameLocale,
        region = regionMap[regionID] or tostring(regionID),
        serverTime = (function()
            if C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime then
                local t = C_DateAndTime.GetCurrentCalendarTime()
                if t then
                    return string.format("%04d-%02d-%02d %02d:%02d", t.year, t.month, t.monthDay, t.hour, t.minute)
                end
            end
            return "N/A"
        end)(),
    }
end

function ExwindTools:GenerateDiagnosticText()
    local env = self:GetEnvironmentInfo()
    local lines = {
        L["=== ExwindTools 诊断信息 ==="],
        string.format(L["插件版本: %s | WTF版本: %d"], env.addonVersion, env.dbVersion),
        string.format(L["游戏版本: %s (Build: %s)"], env.gameVersion, env.gameBuild),
        string.format(L["系统: %s (%s) | 区域: %s | 语言: %s | ElvUI: %s"], env.platform, env.arch, env.region, env.locale,
            env.isElvUI),
        string.format(L["环境: PTR=%s | BetaBuild=%s | RealmID=%s | BetaRealm=%s | 最终IsBeta=%s"], env.isPTR, env.isBeta,
            tostring(env.realmID), env.isBetaRealm, env.isBetaEnv),
        "",
        L["=== 当前状态 ==="],
        string.format(L["职业: %s | 专精: %s"], self.State and self.State.ClassName or "N/A",
            self.State and self.State.SpecName or "N/A"),
        string.format(L["副本: %s | 战斗: %s"], self.State and self.State.InInstance and L["是"] or L["否"],
            self.State and self.State.InCombat and L["是"] or L["否"]),
        "",
        L["=== 依赖库 ==="],
    }
    for name, loaded in pairs(self.LibStatus) do
        table.insert(lines, string.format("%s: %s", name, loaded and "OK" or "MISSING"))
    end
    return table.concat(lines, "\n")
end

--=======================================================================
--========================== 模块管理 ===================================
--=======================================================================
local function MergeDefaults(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then return end
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = dst[k] or {}
            MergeDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

local function CopyDefaultValue(value)
    if type(value) ~= "table" then
        return value
    end
    local copied = {}
    for key, child in pairs(value) do
        copied[CopyDefaultValue(key)] = CopyDefaultValue(child)
    end
    return copied
end

local function BuildAllowedFieldSet(fields, moduleKey, groupName)
    local allowed = {}
    if type(fields) ~= "table" then
        error("DeclareModuleDefaults[" .. moduleKey .. "]: root group '" .. groupName .. "' requires fields", 3)
    end
    for _, field in ipairs(fields) do
        if type(field) ~= "string" or field == "" then
            error("DeclareModuleDefaults[" .. moduleKey .. "]: invalid field in group '" .. groupName .. "'", 3)
        end
        if allowed[field] then
            error("DeclareModuleDefaults[" .. moduleKey .. "]: duplicate field '" .. field .. "'", 3)
        end
        allowed[field] = true
    end
    return allowed
end

-- 默认值 schema 是递归白名单，不是“顶层组名存在即可整表复制”。这样 Grid
-- 导出只投影被声明的字段，运行时残留或误写的嵌套字段不能回流成 EX_DEFAULTS。
local function ProjectDeclaredTable(source, fields, moduleKey, path, strict)
    if type(source) ~= "table" or type(fields) ~= "table" then
        error("DeclareModuleDefaults[" .. moduleKey .. "]: " .. path .. " requires table fields", 3)
    end
    local allowed, projected = {}, {}
    for key, childFields in pairs(fields) do
        if type(key) == "number" then
            if type(childFields) ~= "string" or childFields == "" then
                error("DeclareModuleDefaults[" .. moduleKey .. "]: invalid field in " .. path, 3)
            end
            allowed[childFields] = true
        elseif type(key) == "string" then
            if type(childFields) ~= "table" then
                error(
                    "DeclareModuleDefaults[" ..
                    moduleKey .. "]: nested field " .. path .. "." .. key .. " requires schema",
                    3)
            end
            allowed[key] = childFields
        else
            error("DeclareModuleDefaults[" .. moduleKey .. "]: invalid schema key in " .. path, 3)
        end
    end
    for key, value in pairs(source) do
        local rule = allowed[key]
        if rule == nil then
            if strict then
                error(
                    "DeclareModuleDefaults[" .. moduleKey .. "]: unknown field '" .. path .. "." .. tostring(key) .. "'",
                    3)
            end
        else
            -- 叶子值可以合法地是 false；不能用 a and b or c 选择分支，
            -- 否则 CopyDefaultValue(false) 会错误落进嵌套表投影。
            if rule == true then
                projected[key] = CopyDefaultValue(value)
            else
                projected[key] = ProjectDeclaredTable(value, rule, moduleKey, path .. "." .. key, strict)
            end
        end
    end
    return projected
end

local function CompileModuleDefaultDeclaration(moduleKey, declaration, schema)
    if type(declaration) ~= "table" then
        error("DeclareModuleDefaults[" .. moduleKey .. "]: declaration must be a table", 3)
    end
    if type(schema) ~= "table" or #schema == 0 then
        error("DeclareModuleDefaults[" .. moduleKey .. "]: schema must be a non-empty array", 3)
    end

    local compiled, handledGroups, writtenTargets = {}, {}, {}
    for _, rule in ipairs(schema) do
        local groupName = rule and rule.group
        if type(groupName) ~= "string" or groupName == "" then
            error("DeclareModuleDefaults[" .. moduleKey .. "]: each schema rule requires group", 3)
        end
        if handledGroups[groupName] then
            error("DeclareModuleDefaults[" .. moduleKey .. "]: duplicate schema group '" .. groupName .. "'", 3)
        end
        handledGroups[groupName] = true

        local source = declaration[groupName]
        if type(source) ~= "table" then
            error("DeclareModuleDefaults[" .. moduleKey .. "]: declaration group '" .. groupName .. "' must be a table",
                3)
        end

        if rule.root == true then
            local allowed = BuildAllowedFieldSet(rule.fields, moduleKey, groupName)
            for field, value in pairs(source) do
                if not allowed[field] then
                    error(
                        "DeclareModuleDefaults[" ..
                        moduleKey .. "]: unknown field '" .. groupName .. "." .. tostring(field) .. "'", 3)
                end
                if writtenTargets[field] then
                    error("DeclareModuleDefaults[" .. moduleKey .. "]: duplicate runtime field '" .. field .. "'", 3)
                end
                writtenTargets[field] = true
                compiled[field] = CopyDefaultValue(value)
            end
        else
            local target = rule.target or groupName
            if type(target) ~= "string" or target == "" then
                error("DeclareModuleDefaults[" .. moduleKey .. "]: invalid target for group '" .. groupName .. "'", 3)
            end
            if writtenTargets[target] then
                error("DeclareModuleDefaults[" .. moduleKey .. "]: duplicate runtime table '" .. target .. "'", 3)
            end
            writtenTargets[target] = true
            compiled[target] = ProjectDeclaredTable(source, rule.fields, moduleKey, groupName, true)
        end
    end

    for groupName in pairs(declaration) do
        if not handledGroups[groupName] then
            error("DeclareModuleDefaults[" .. moduleKey .. "]: undeclared source group '" .. tostring(groupName) .. "'",
                3)
        end
    end

    return compiled
end

function ExwindTools:DeclareModuleDefaults(moduleKey, declaration, schema)
    if type(moduleKey) ~= "string" or moduleKey == "" then
        error("DeclareModuleDefaults: moduleKey must be non-empty string", 2)
    end
    if self.ModuleDefaultDeclarations[moduleKey] then
        error("DeclareModuleDefaults[" .. moduleKey .. "]: declaration already registered", 2)
    end
    BindModuleDBOwner(moduleKey)

    local compiled = CompileModuleDefaultDeclaration(moduleKey, declaration, schema)
    self.ModuleDefaultDeclarations[moduleKey] = {
        declaration = CopyDefaultValue(declaration),
        schema = schema,
        compiled = compiled,
    }
    return CopyDefaultValue(compiled)
end

-- 模块自己的 MODULE_SPEC.defaults 就是唯一 DB 声明来源。此处只提供无模块知识的
-- 编译器：root 内字段写入 ModuleDB 根，其余组保持为同名嵌套表。
local function InferModuleSpecFields(value, moduleKey, path)
    if type(value) ~= "table" then
        error("DeclareModuleSpecDefaults[" .. moduleKey .. "]: " .. path .. " must be a table", 3)
    end
    local fields = {}
    for key, child in pairs(value) do
        if type(key) ~= "string" or key == "" then
            error("DeclareModuleSpecDefaults[" .. moduleKey .. "]: invalid key in " .. path, 3)
        end
        if type(child) == "table" then
            fields[key] = InferModuleSpecFields(child, moduleKey, path .. "." .. key)
        else
            fields[#fields + 1] = key
        end
    end
    return fields
end

function ExwindTools:DeclareModuleSpecDefaults(moduleKey, declaration)
    if type(declaration) ~= "table" or type(declaration.root) ~= "table" then
        error("DeclareModuleSpecDefaults[" .. tostring(moduleKey) .. "]: declaration.root must be a table", 2)
    end
    local schema = { { group = "root", root = true, fields = {} } }
    for key in pairs(declaration.root) do
        if type(key) ~= "string" or key == "" then
            error("DeclareModuleSpecDefaults[" .. moduleKey .. "]: invalid root key", 2)
        end
        schema[1].fields[#schema[1].fields + 1] = key
    end
    local groups = {}
    for groupName in pairs(declaration) do
        if groupName ~= "root" then groups[#groups + 1] = groupName end
    end
    table.sort(groups)
    for _, groupName in ipairs(groups) do
        schema[#schema + 1] = {
            group = groupName,
            fields = InferModuleSpecFields(declaration[groupName], moduleKey, groupName),
        }
    end
    return self:DeclareModuleDefaults(moduleKey, declaration, schema)
end

function ExwindTools:ExportModuleDefaults(moduleKey)
    local registered = self.ModuleDefaultDeclarations[moduleKey]
    if not registered then
        error("ExportModuleDefaults[" .. tostring(moduleKey) .. "]: module has not declared standard defaults", 2)
    end

    local db = self:GetModuleDB(moduleKey)
    local declaration = {}
    for _, rule in ipairs(registered.schema) do
        local group = {}
        if rule.root == true then
            for _, field in ipairs(rule.fields) do
                if db[field] ~= nil then
                    group[field] = CopyDefaultValue(db[field])
                end
            end
        else
            local target = rule.target or rule.group
            if type(db[target]) ~= "table" then
                error("ExportModuleDefaults[" .. moduleKey .. "]: runtime table '" .. target .. "' is missing", 2)
            end
            group = ProjectDeclaredTable(db[target], rule.fields, moduleKey, rule.group, false)
        end
        declaration[rule.group] = group
    end
    return declaration
end

function ExwindTools:IsModuleEnabled(moduleKey)
    -- 1. 检查配置是否启用。和 SetModuleEnabled/模块管理卡片保持同一口径：
    -- nil 视为默认启用（与 DefaultEnabled ~= false 的初始化语义一致），
    -- 只有显式写入 false 才是禁用；不能用 ~= true 把 nil 当成禁用。
    if self.DB.LoadByKey[moduleKey] == false then
        return false
    end

    -- 2. 检查静态定义的屏蔽规则 (BlockBeta)
    local idx = self.ModuleIndexByKey[moduleKey]
    if idx then
        local meta = self.ModuleList[idx]
        if meta and meta.BlockBeta and not self.IsBeta then
            return false -- 如果标记了 BlockBeta 且当前不是 Beta 环境，则视为禁用
        end
    end

    return true
end

function ExwindTools:GetModuleDB(moduleKey, defaults)
    if type(moduleKey) ~= "string" or moduleKey == "" then
        error("GetModuleDB: moduleKey must be non-empty string", 2)
    end
    local declared = self.ModuleDefaultDeclarations[moduleKey]
    if declared and defaults ~= nil then
        error("GetModuleDB[" .. moduleKey .. "]: declared module must not pass a second defaults table", 2)
    end
    local storage = self:GetModuleDBStorage(moduleKey)
    storage.ModuleDB[moduleKey] = storage.ModuleDB[moduleKey] or {}
    if declared then
        MergeDefaults(storage.ModuleDB[moduleKey], declared.compiled)
    elseif type(defaults) == "table" then
        MergeDefaults(storage.ModuleDB[moduleKey], defaults)
    end
    return storage.ModuleDB[moduleKey]
end

function ExwindTools:RegisterModuleLayout(moduleKey, layoutData)
    if type(moduleKey) == "string" and type(layoutData) == "table" then
        self.RegisteredLayouts[moduleKey] = layoutData
    end
end

local function OwnerBelongsToModule(owner, moduleKey)
    if owner == moduleKey then
        return true
    end
    if type(owner) ~= "string" or type(moduleKey) ~= "string" then
        return false
    end

    return string.sub(owner, 1, #moduleKey + 1) == (moduleKey .. ".")
        or string.sub(owner, 1, #moduleKey + 1) == (moduleKey .. "_")
end

function ExwindTools:DisableModuleRuntime(moduleKey)
    if type(moduleKey) ~= "string" or moduleKey == "" then
        return false
    end

    for eventName, handlers in pairs(self.EventHandlers or {}) do
        local ownersToRemove = {}
        for owner in pairs(handlers) do
            if OwnerBelongsToModule(owner, moduleKey) then
                ownersToRemove[#ownersToRemove + 1] = owner
            end
        end
        for _, owner in ipairs(ownersToRemove) do
            self:UnregisterEvent(eventName, owner)
        end
    end

    for stateKey, callbacks in pairs(self.StateCallbacks or {}) do
        local ownersToRemove = {}
        for owner in pairs(callbacks) do
            if OwnerBelongsToModule(owner, moduleKey) then
                ownersToRemove[#ownersToRemove + 1] = owner
            end
        end
        for _, owner in ipairs(ownersToRemove) do
            self:UnwatchState(stateKey, owner)
        end
    end

    for stateKey, watchers in pairs(self.DeltaWatchers or {}) do
        local ownersToRemove = {}
        for owner in pairs(watchers) do
            if OwnerBelongsToModule(owner, moduleKey) then
                ownersToRemove[#ownersToRemove + 1] = owner
            end
        end
        for _, owner in ipairs(ownersToRemove) do
            self:UnwatchStateDelta(stateKey, owner)
        end
    end

    for eventName, moduleWatchers in pairs(self.WatchEvenRegistry or {}) do
        local modulesToRemove = {}
        for owner in pairs(moduleWatchers) do
            if OwnerBelongsToModule(owner, moduleKey) then
                modulesToRemove[#modulesToRemove + 1] = owner
            end
        end
        for _, owner in ipairs(modulesToRemove) do
            self.UnwatchEven(eventName, owner)
        end
    end

    self.ModuleStatus[moduleKey] = "disabled"
    return true
end

function ExwindTools:SetModuleEnabled(moduleKey, enabled)
    if type(moduleKey) ~= "string" or moduleKey == "" then
        return false
    end

    enabled = enabled and true or false

    if not self.DB or not self.DB.LoadByKey then
        return false
    end

    -- 必须和调用方（模块管理卡片）的判定口径一致：nil 视为"已启用"，只有
    -- 显式 false 才是禁用。之前这里用 == true（nil 判为禁用）而卡片用
    -- ~= false（nil 判为启用），两者相反：当某个模块字段仍是 nil 时，UI
    -- 显示"已启用/可禁用"，点击后算出 enabled=false 传进来，这里却认为
    -- "当前已经是禁用"（currentEnabled=false）而直接短路 return，真实值
    -- 永远停留在 nil，导致该模块的启用/禁用按钮永久失效，只有"全部启用"
    -- 无条件写入 true 才能把 nil 打破。
    local currentEnabled = self.DB.LoadByKey[moduleKey] ~= false
    if currentEnabled == enabled then
        return false
    end

    self.DB.LoadByKey[moduleKey] = enabled

    local idx = self.ModuleIndexByKey[moduleKey]
    if idx and self.DB.Load then
        self.DB.Load[idx] = enabled
    end

    if enabled then
        self.ModuleStatus[moduleKey] = "pending_reload"
    else
        self:DisableModuleRuntime(moduleKey)
    end

    return true
end

local function ShowMissingExwindToolsWarning()
    local exists = C_AddOns and C_AddOns.DoesAddOnExist and C_AddOns.DoesAddOnExist("ExwindTools")
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("ExwindTools")
    local loadable, reason
    if C_AddOns and C_AddOns.GetAddOnInfo then
        local _, _, _, addonLoadable, addonReason = C_AddOns.GetAddOnInfo("ExwindTools")
        loadable = addonLoadable
        reason = addonReason
    end
    local message

    if not exists then
        message = L["你并未安装 ExwindTools，无法打开 ExwindTools 设置面板。"]
    elseif not loaded then
        if loadable == false and reason and reason ~= "" then
            message = string.format(L["ExwindTools 当前未载入，无法打开设置面板。\n原因：%s"], tostring(reason))
        else
            message = L["ExwindTools 当前未载入，无法打开 ExwindTools 设置面板。"]
        end
    else
        return false
    end

    if not StaticPopupDialogs["EXWINDTOOLS_MISSING_WARNING"] then
        StaticPopupDialogs["EXWINDTOOLS_MISSING_WARNING"] = {
            text = "%s",
            button1 = L["确定"],
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end

    StaticPopup_Show("EXWINDTOOLS_MISSING_WARNING", message)
    ExwindTools:Print(message)
    return true
end
function ExwindTools:OpenConfig(moduleKey)
    if ShowMissingExwindToolsWarning() then
        return
    end

    if not self.UI or not self.UI.Toggle then return end

    -- Unified Shell 已注册 Tools Provider 时，所有 Tools 入口都走同一外壳。
    -- 这里传 route 而不是操作旧 MainFrame，确保模块页仍由 Tools 自己的
    -- CurrentPage / CurrentModule / RefreshContent 处理。
    local unified = self.UnifiedPanel
    if unified and unified.Providers and unified.Providers.tools then
        unified:Show("tools", moduleKey and { moduleKey = moduleKey } or nil)
        return
    end

    if moduleKey then
        self.UI.CurrentPage = "ModuleSettings"
        self.UI.CurrentModule = moduleKey
    end

    if not self.UI.MainFrame or not self.UI.MainFrame:IsShown() then
        self.UI:Toggle()
    else
        self.UI:RefreshContent()
        -- [v4.7] 确保窗口在最前
        self.UI.MainFrame:Raise()
    end
end

--=======================================================================
--========================== 命令行系统 =================================
--=======================================================================
function ExwindTools:Print(msg, ...)
    print("|cffA330C9ExwindTools|r " .. (select("#", ...) > 0 and string.format(msg, ...) or msg))
end

function ExwindTools:RegisterChatCommand(slash, func)
    local cmd = slash:upper()
    _G["SLASH_" .. cmd .. "1"] = "/" .. slash
    SlashCmdList[cmd] = func
end

-- 核心命令
ExwindTools:RegisterChatCommand("ex", function(input)
    local arg = (input or ""):trim():lower()

    if arg == "" then
        if ExwindTools.PanelRouter and ExwindTools.PanelRouter.Toggle then
            ExwindTools.PanelRouter:Toggle("tools")
        elseif ExwindTools.UI and ExwindTools.UI.Toggle then
            ExwindTools.UI:Toggle()
        else
            ExwindTools:OpenConfig()
        end
        return
    end

    if arg == "dev" or arg == "edit" then
        ExwindTools.State.DevMode = not ExwindTools.State.DevMode
        print(L["|cffA330C9[ExwindTools]|r 开发者模式: "] ..
            (ExwindTools.State.DevMode and L["|cff00ff00[启用]|r"] or L["|cffff0000[禁用]|r"]))
        if ExwindTools.UI and ExwindTools.UI.RefreshContent then ExwindTools.UI:RefreshContent() end
        return
    end

    if arg == "debug" then
        ExwindTools.DebugMode = not ExwindTools.DebugMode
        print("|cffA330C9[ExwindTools]|r DEBUG: " ..
            (ExwindTools.DebugMode and L["|cff00ff00[启用]|r"] or L["|cffff0000[禁用]|r"]))
        return
    end

    if arg == "edmode" then
        ExwindTools.UI:ToggleEditMode()
        return
    end

    if arg == "diag" then
        local root = _G.ExwindPlayerStatsAnchor
        if not root then
            print("|cffff9900[EX-DIAG]|r 找不到 ExwindPlayerStatsAnchor，模块可能未加载/未启用")
            return
        end
        local function Scan(frame, depth)
            local mouseEnabled = frame.IsMouseEnabled and frame:IsMouseEnabled()
            local name = frame.GetName and frame:GetName() or tostring(frame)
            local strata = frame.GetFrameStrata and frame:GetFrameStrata() or "?"
            local level = frame.GetFrameLevel and frame:GetFrameLevel() or "?"
            local shown = frame.IsShown and frame:IsShown()
            print(string.format("|cff88ff00[EX-DIAG]|r %s%s mouse=%s shown=%s strata=%s level=%s",
                string.rep("  ", depth), tostring(name), tostring(mouseEnabled), tostring(shown), tostring(strata),
                tostring(level)))
            local n = frame.GetNumChildren and frame:GetNumChildren() or 0
            for i = 1, n do
                local child = select(i, frame:GetChildren())
                if child then Scan(child, depth + 1) end
            end
        end
        print("|cff88ff00[EX-DIAG]|r ===== 开始扫描 ExwindPlayerStatsAnchor 及所有子 Frame =====")
        Scan(root, 0)
        print("|cff88ff00[EX-DIAG]|r ===== 扫描结束，mouse=true 的那一行就是挡鼠标的 Frame =====")
        return
    end

    if arg == "re" then
        C_UI.Reload(); return
    end

    ExwindTools:OpenConfig()
end)

ExwindTools:RegisterChatCommand("exwind", function(input)
    local arg = (input or ""):trim()
    if arg == "" and ExwindTools.UI and ExwindTools.UI.Toggle then
        ExwindTools.UI:Toggle()
        return
    end
    ExwindTools:OpenConfig()
end)

ExwindTools:RegisterChatCommand("extre", function()
    ExwindTools:ResetAddonModuleStorage("TOOLS")
    C_UI.Reload()
end)

-- /rl 快捷重载 (兼容未安装 ACP 的用户，已装 ACP 则被覆盖，功能一致)
ExwindTools:RegisterChatCommand("rl", function()
    C_UI.Reload()
end)

ExwindTools:RegisterChatCommand("exstate", function()
    print(L["|cffA330C9[ExwindTools] 当前 States:|r"])
    if not ExwindTools.State then
        print(L["  State 未初始化"]); return
    end

    local keys = {}
    for k in pairs(ExwindTools.State) do table.insert(keys, k) end
    table.sort(keys)

    for _, k in ipairs(keys) do
        local v = ExwindTools.State[k]
        local vStr = type(v) == "number" and string.format("%.2f", v) or tostring(v)
        print(string.format("  |cffcccccc[%s]|r = |cff00ff00%s|r", k, vStr))
    end
end)



--=======================================================================
--========================== 小地图按钮 (Minimap Button) ================
--=======================================================================
function ExwindTools:IsMinimapButtonHidden()
    db.Minimap = db.Minimap or { hide = false }
    return db.Minimap.hide == true
end

function ExwindTools:SetMinimapButtonHidden(hidden)
    db.Minimap = db.Minimap or { hide = false }
    db.Minimap.hide = hidden and true or false

    local LDBIcon = LibStub("LibDBIcon-1.0", true)
    if not LDBIcon then return end
    if LDBIcon:IsRegistered("ExwindTools") then
        LDBIcon:Refresh("ExwindTools", db.Minimap)
    end
end

-- 统一小地图入口：不再区分 EXBoss / ExwindTools，只要 ExwindCore 加载就创建，
-- 点击后打开三合一统一面板本身（保留上次打开的 Provider），不再绑定某一个插件。
local function SyncMinimapButton()
    local LDB = LibStub("LibDataBroker-1.1", true)
    local LDBIcon = LibStub("LibDBIcon-1.0", true)
    if not LDB or not LDBIcon then return end

    local EX_LDB = LDB:NewDataObject("ExwindTools", {
        type = "launcher",
        text = "EXWIND",
        icon = [[Interface\AddOns\ExwindCore\Textures\LOGO\EXUI.jpg]],
        OnClick = function(self, button)
            if button == "LeftButton" then
                if ExwindTools.UnifiedPanel and ExwindTools.UnifiedPanel.Toggle then
                    ExwindTools.UnifiedPanel:Toggle()
                else
                    ExwindTools:OpenConfig()
                end
            elseif button == "RightButton" then
                ExwindTools.UI:ToggleEditMode()
            end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine("|cffA330C9Exwind|r " .. ExwindTools.VERSION)
            tt:AddLine(" ")
            tt:AddLine(string.format("|cff00ff00%s|r %s", L["左键:"], L["打开 Exwind 面板"]))
            tt:AddLine(string.format("|cff00ff00%s|r %s", L["右键:"], L["切换编辑模式"]))
        end,
    })

    -- 使用 EXCORE12S2 存储位置信息
    db.Minimap = db.Minimap or { hide = false }
    if not LDBIcon:IsRegistered("ExwindTools") then
        LDBIcon:Register("ExwindTools", EX_LDB, db.Minimap)
    end
    LDBIcon:Refresh("ExwindTools", db.Minimap)
end

C_Timer.After(0.5, SyncMinimapButton)

EXDebug(L["ExwindTools 核心加载完成"])
