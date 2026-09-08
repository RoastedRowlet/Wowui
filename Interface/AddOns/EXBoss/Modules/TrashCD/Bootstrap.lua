---@diagnostic disable: undefined-global

ExBoss = ExBoss or {}
ExBoss.Trash = ExBoss.Trash or {}
ExBoss.Trash.GUI = ExBoss.Trash.GUI or {}
ExBoss.Trash.Runtime = ExBoss.Trash.Runtime or {}
ExBoss.Trash.Data = ExBoss.Trash.Data or {}
ExBoss.TrashCD = ExBoss.TrashCD or {}

function ExBoss.Trash.IsEnabled()
    local Store = ExBoss.TrashCD and ExBoss.TrashCD.Store
    if Store and type(Store.IsEnabled) == "function" then
        return Store.IsEnabled()
    end
    return false
end
