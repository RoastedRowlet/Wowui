-- EXBoss 与统一编辑模式之间唯一的设置页边界。
-- 它只路由已声明页面，不注册编辑模式、不创建预览、不持有模块状态。

local ExwindTools = _G.ExwindTools
local EXUI = ExwindTools and ExwindTools.UI
if not EXUI then return end

-- 只能列出实际已 RegisterEditableModule 的 settingsPage。这个表是编辑模式
-- 右键“定位设置”的唯一入口白名单；新增可编辑模块时必须同时更新这里并通过路由测试。
local ROUTABLE_SETTINGS_PAGES = {
    timerbar = true,
    bunbar = true,
    countdown = true,
    flashtextmedium = true,
    ringprogress = true,
    iconalert = true,
    castprogressbar = true,
    extrashieldbar = true,
    mythiccast = true,
    interrupttracker = true,
}

EXUI:RegisterModuleSettingsRouter("EXBoss", function(settingsPage)
    if ROUTABLE_SETTINGS_PAGES[settingsPage] ~= true then
        error("EXBoss settings router received undeclared page: " .. tostring(settingsPage), 2)
    end

    local panel = ExBoss and ExBoss.UI and ExBoss.UI.Panel
    if not panel or type(panel.Show) ~= "function" or type(panel.SetTab) ~= "function" then
        error("EXBoss settings panel is unavailable", 2)
    end
    panel:Show()
    panel:SetTab(settingsPage)
end)
