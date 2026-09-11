---@diagnostic disable: undefined-global
-- 毒牙祭坛专用生产者。身份与战斗条件仅消费小怪 State，不自行推理 NPC。
local NPC_IDS = {
    [263112] = true,
}
local INSTANCE_ID = 2993
local REFRESH_INTERVAL = .33
local OWNER = "ExBoss.AltarOfFangs.TrashHealth"
local Tools = _G.ExwindTools
local State = ExBoss.Trash.State
local Display = ExBoss.UI.DungeonExtras
local L = ExBoss.L
local tracked, dirty = {}, {}
local timer, running
local generation = 0

local function Allowed()
    return Tools.State.InstanceID == INSTANCE_ID and Display:IsEnabled("altarTrashHealth")
        and not Display:IsWorldEditing()
end
local function Matches(row)
    return row and row.active == true and row.exists == true and row.inCombat == true
        and row.deadAt == nil and NPC_IDS[row.npcID] == true
end
local function Remove(unit)
    dirty[unit] = nil
    if tracked[unit] then
        Display:RemoveHealth(unit)
        tracked[unit] = nil
    end
    if not next(dirty) and timer then timer:Cancel(); timer = nil end
end
local function Refresh(unit)
    local row = State.GetUnit(unit)
    if not running or not Matches(row) or not UnitExists(row.unit) or UnitIsDeadOrGhost(row.unit) then
        Remove(unit)
        return
    end
    Display:UpdateHealth(unit, row.unit, row.lastResolvedName or L["小怪"])
end
local function Schedule(unit)
    dirty[unit] = true
    if timer then return end
    local currentGeneration = generation
    timer = C_Timer.NewTimer(REFRESH_INTERVAL, function()
        timer = nil
        if currentGeneration ~= generation or not running then return end
        local batch = dirty
        dirty = {}
        for token in pairs(batch) do Refresh(token) end
    end)
end
local function ReconcileUnit(unit)
    local row = State.GetUnit(unit)
    if not Matches(row) then Remove(unit); return end
    local existing = tracked[unit]
    if not existing or existing.addedAt ~= row.addedAt or existing.npcID ~= row.npcID then
        Remove(unit)
        tracked[unit] = { addedAt = row.addedAt, npcID = row.npcID }
        Refresh(unit) -- 新出现/身份变化立即显示，后续血量事件组批。
    else
        Schedule(unit)
    end
end
local function Stop()
    running = false
    generation = generation + 1
    if timer then timer:Cancel(); timer = nil end
    wipe(dirty)
    wipe(tracked)
    Tools:UnregisterEvent("UNIT_HEALTH", OWNER)
    Tools:UnregisterEvent("UNIT_MAXHEALTH", OWNER)
    Display:ClearHealth()
end
local function OnHealth(_, unit)
    if not tracked[unit] then return end
    if not Matches(State.GetUnit(unit)) or UnitIsDeadOrGhost(unit) then Remove(unit); return end
    Schedule(unit)
end
local function Reconcile()
    if not Allowed() then Stop(); return end
    if not running then
        running = true
        Tools:RegisterEvent("UNIT_HEALTH", OWNER, OnHealth)
        Tools:RegisterEvent("UNIT_MAXHEALTH", OWNER, OnHealth)
    end
    for unit in pairs(tracked) do if not Matches(State.GetUnit(unit)) then Remove(unit) end end
    for unit in pairs(State.GetUnits()) do ReconcileUnit(unit) end
end
Tools:RegisterEvent("EXBOSS_TRASH_STATE_CHANGED", OWNER, function(_, unit)
    if not running then return end
    if unit then ReconcileUnit(unit) else Stop(); Reconcile() end
end)
Tools:RegisterEvent("EXBOSS_DUNGEON_EXTRAS_CHANGED", OWNER, Reconcile)
Tools:WatchState("InstanceID", OWNER, Reconcile)
Tools:RegisterEvent("PLAYER_ENTERING_WORLD", OWNER, Reconcile)
Reconcile()
