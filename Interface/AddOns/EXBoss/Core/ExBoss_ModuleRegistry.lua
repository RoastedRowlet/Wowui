---@diagnostic disable: undefined-global
-- =============================================================
-- ExBoss 模块载入管理系统
-- 设计见 EXWIND-DEV/ExwindCore/模块SOP标准.md §6
-- =============================================================

ExBoss = ExBoss or {}
if ExBoss._moduleRegistryInstalled == true then
    return
end
ExBoss._moduleRegistryInstalled = true

-- 单一真源：ExBoss.Tools.* 系列模块的元数据清单。
-- 现状分散在 ExBossGUI/SettingsPage/ToolsPage.lua 的 ITEMS、GlobalSettingsPage.lua 的 pageMap、
-- PanelFrame.lua 的 SetTab 硬编码判断、ExwindCore/Core/ExwindTools.lua 的 OpenConfig 映射表，
-- 后续逐步改成读这里，不再各自维护一份。
--
-- 注意：这里不进 ExwindTools.ModuleList（那是 ExwindTools 自身模块专用，架构上通过
-- ExwindTools:OpenConfig 的 "ExBoss." 前缀特判把 EXBoss 模块排除在外），这是 EXBoss 自己
-- 物理独立的一套载入管理系统，数据落在 EXBOSS12S2，不是 EXBOSS12S2。
ExBoss.ModuleList = {
    -- { Key = "ExBoss.TargetAlert",         Name = "被点名提示",     PanelTab = "targetalert" }, -- 临时停用
    { Key = "ExBoss.Tools.MythicCast",       Name = "大米怪物施法",   PanelTab = "mythiccast" },
    { Key = "ExBoss.Tools.InterruptTracker", Name = "队友打断监控",   PanelTab = "interrupttracker" },
}

ExBoss.ModuleIndexByKey = {}
for i, meta in ipairs(ExBoss.ModuleList) do
    ExBoss.ModuleIndexByKey[meta.Key] = i
end

-- 复用现状里各文件已在用的裸全局约定（`EXBOSS12S2 = EXBOSS12S2 or {}`），不新建命名空间，
-- 也不占用 ExBoss.lua 已声明、语义不同的 ExBoss.DB（那是数据加载模块，有自己的 :Init()）。
_G.EXBOSS12S2 = _G.EXBOSS12S2 or {}
local db = _G.EXBOSS12S2
db.LoadByKey = db.LoadByKey or {}

for _, meta in ipairs(ExBoss.ModuleList) do
    if db.LoadByKey[meta.Key] == nil then
        db.LoadByKey[meta.Key] = (meta.DefaultEnabled ~= false)
    end
end

--- 判断一个 ExBoss.Tools.* / ExBoss.TargetAlert 模块当前是否启用（载入门控用）。
--- 模块文件应在 EX_RegisterLayout() 之后、其余业务逻辑之前调用：
---   if not ExBoss:IsModuleEnabled(EXWIND_MODULE_KEY) then return end
--- @param moduleKey string
--- @return boolean
function ExBoss:IsModuleEnabled(moduleKey)
    -- nil 视为默认启用，和上面 38-42 行 DefaultEnabled ~= false 的初始化
    -- 语义保持一致；只有显式写入 false 才是禁用。见 ExwindCore/Core/
    -- ExwindTools.lua 的 SetModuleEnabled/IsModuleEnabled 同一处修正说明。
    return db.LoadByKey[moduleKey] ~= false
end

--- 根据 moduleKey 反查 ExBoss.ModuleList 里的元数据（面板跳转等场景用）。
--- @param moduleKey string
--- @return table|nil
function ExBoss:GetModuleMeta(moduleKey)
    local idx = self.ModuleIndexByKey[moduleKey]
    return idx and self.ModuleList[idx] or nil
end
