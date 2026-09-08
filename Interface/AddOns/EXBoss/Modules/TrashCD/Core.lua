---@diagnostic disable: undefined-global

ExBoss = ExBoss or {}
ExBoss.Trash = ExBoss.Trash or {}
ExBoss.TrashCD = ExBoss.TrashCD or {}

local Core = ExBoss.TrashCD.Core or {}
ExBoss.TrashCD.Core = Core
ExBoss.Trash.Core = Core

local Store = ExBoss.TrashCD.Store

local monitorUIEnabled = false

function Core.IsEnabled()
    return Store and Store.IsEnabled and Store.IsEnabled() == true or false
end

function Core.IsMonitorEnabled()
    return Store and Store.IsMonitorEnabled and Store.IsMonitorEnabled() == true or false
end

function Core.ShouldRunMonitor()
    return Core.IsMonitorEnabled() == true and IsInInstance() == true
end

function Core.SetMonitorUIEnabled(enabled)
    monitorUIEnabled = (enabled == true)
end

function Core.IsMonitorUIEnabled()
    return monitorUIEnabled == true
end

function Core.GetRuntimeSummary()
    local db = Store and Store.GetRuntimeSettings and Store.GetRuntimeSettings() or {}
    return {
        enabled = db.enabled ~= false,
        monitorEnabled = db.monitorEnabled ~= false,
        monitorUIEnabled = monitorUIEnabled == true,
        outputEnabled = db.enabled ~= false,
        useTimelineScriptEvent = db.useTimelineScriptEvent ~= false,
    }
end
