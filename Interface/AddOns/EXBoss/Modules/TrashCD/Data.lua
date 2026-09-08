---@diagnostic disable: undefined-global

ExBoss = ExBoss or {}
ExBoss.Trash = ExBoss.Trash or {}
ExBoss.TrashCD = ExBoss.TrashCD or {}

local Data = ExBoss.TrashCD.Data or {}
ExBoss.TrashCD.Data = Data
ExBoss.Trash.Data = Data

local ExwindTools = _G.ExwindTools

local encounterMapNameByInstanceID
local encounterMapNameByMapID
local trashMapIDByNameKey
local trashPresetRootCache
local areaNameByID = {}
local wmoAreaIDsByName

function Data.NormalizeNameKey(name)
    local s = tostring(name or "")
    s = s:lower()
    s = s:gsub("%s+", "")
    s = s:gsub("[：:，,。%.！!？?·%-_—~`'\"%(%[%{%)%]%}]", "")
    return s
end

local function NormalizeZoneText(text)
    local s = tostring(text or "")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    s = s:gsub("%s+", " ")
    return s
end

function Data.GetCurrentZoneText()
    local state = ExwindTools and ExwindTools.State or nil
    local text = NormalizeZoneText(state and (state.ZoneText or state.MinimapZoneText) or "")
    if text ~= "" then
        return text
    end
    if type(GetMinimapZoneText) == "function" then
        local ok, zoneText = pcall(GetMinimapZoneText)
        if ok then
            text = NormalizeZoneText(zoneText)
            if text ~= "" then
                return text
            end
        end
    end
    return ""
end

function Data.GetAreaInfoName(areaID)
    local id = tonumber(areaID)
    if not id or id <= 0 then
        return ""
    end
    if areaNameByID[id] ~= nil then
        return areaNameByID[id]
    end
    local name = ""
    if C_Map and type(C_Map.GetAreaInfo) == "function" then
        local ok, value = pcall(C_Map.GetAreaInfo, id)
        if ok then
            name = NormalizeZoneText(value)
        end
    end
    areaNameByID[id] = name
    return name
end

-- WMOAreaTable 与 C_Map 区域表是两套 ID。这里不读取客户端语言，
-- 只把 Excel 导出的所有语言名称反查为 WMO ID；任一语言文本命中即可。
local function GetWMOAreaIDsByName()
    if type(wmoAreaIDsByName) == "table" then
        return wmoAreaIDsByName
    end
    local out = {}
    local traitsRoot = Data.GetTrashMobTraitsRoot and Data.GetTrashMobTraitsRoot() or nil
    local namesByID = type(traitsRoot) == "table" and traitsRoot.wmoAreaNamesByID or nil
    for rawID, nameSet in pairs(type(namesByID) == "table" and namesByID or {}) do
        local areaID = tonumber(rawID)
        if areaID and type(nameSet) == "table" then
            for _, rawName in pairs(nameSet) do
                local name = NormalizeZoneText(rawName)
                if name ~= "" then
                    out[name] = out[name] or {}
                    out[name][areaID] = true
                end
            end
        end
    end
    wmoAreaIDsByName = out
    return out
end

function Data.GetCurrentWMOAreaSet()
    local zoneText = Data.GetCurrentZoneText()
    if zoneText == "" then
        return {}
    end
    return GetWMOAreaIDsByName()[zoneText] or {}
end

function Data.IsCurrentPlacementID(id)
    local n = tonumber(id)
    if not n or n <= 0 then
        return false
    end
    local state = ExwindTools and ExwindTools.State or nil
    local currentMapID = tonumber(state and state.MapID) or 0
    if currentMapID > 0 and currentMapID == n then
        return true
    end

    local zoneText = Data.GetCurrentZoneText()
    if zoneText == "" then
        return false
    end
    local areaName = Data.GetAreaInfoName(n)
    return areaName ~= "" and areaName == zoneText
end

function Data.IsCurrentPlacementSetAllowed(mapSet)
    if type(mapSet) ~= "table" then
        return true
    end
    local state = ExwindTools and ExwindTools.State or nil
    local currentMapID = tonumber(state and state.MapID) or 0
    local zoneText = Data.GetCurrentZoneText()
    if currentMapID <= 0 and zoneText == "" then
        return true
    end
    for id in pairs(mapSet) do
        if Data.IsCurrentPlacementID(id) then
            return true
        end
    end
    return false
end

function Data.IsCurrentMapIDSetAllowed(mapSet)
    if type(mapSet) ~= "table" then
        return true
    end
    local state = ExwindTools and ExwindTools.State or nil
    local currentMapID = tonumber(state and state.MapID) or 0
    return currentMapID > 0 and mapSet[currentMapID] == true
end

function Data.IsCurrentMinimapAreaSetAllowed(areaSet)
    if type(areaSet) ~= "table" then
        return true
    end
    local zoneText = Data.GetCurrentZoneText()
    if zoneText == "" then
        return false
    end
    for areaID in pairs(areaSet) do
        local areaName = Data.GetAreaInfoName(areaID)
        if areaName ~= "" and areaName == zoneText then
            return true
        end
    end
    return false
end

function Data.IsCurrentWMOAreaSetAllowed(areaSet)
    if type(areaSet) ~= "table" then
        return true
    end
    local currentSet = Data.GetCurrentWMOAreaSet()
    for areaID in pairs(areaSet) do
        if currentSet[tonumber(areaID)] == true then
            return true
        end
    end
    return false
end

function Data.GetTrashMobTraitsRoot()
    local api = _G.EXBossData
    if type(api) == "table" and type(api.GetTrashMobTraitsRoot) == "function" then
        local ok, data = pcall(api.GetTrashMobTraitsRoot)
        if ok and type(data) == "table" then
            return data
        end
    end
    local raw = rawget(_G, "EXBOSS_TRASH_MOB_TRAITS")
    return type(raw) == "table" and raw or { rows = {} }
end

function Data.GetTrashCDDataRoot()
    local api = _G.EXBossData
    if type(api) == "table" and type(api.GetTrashCDDataRoot) == "function" then
        local ok, data = pcall(api.GetTrashCDDataRoot)
        if ok and type(data) == "table" then
            return data
        end
    end
    local raw = rawget(_G, "EXBOSS_TRASH_CD_DATA")
    return type(raw) == "table" and raw or {}
end

function Data.GetTrashCDPresetRoot()
    if trashPresetRootCache ~= nil then
        return trashPresetRootCache
    end
    local api = _G.EXBossData
    if type(api) == "table" and type(api.GetTrashCDPresetRoot) == "function" then
        local ok, data = pcall(api.GetTrashCDPresetRoot)
        if ok and type(data) == "table" then
            trashPresetRootCache = data
            return trashPresetRootCache
        end
    end
    local raw = rawget(_G, "EXBOSS_TRASH_CD_PRESET")
    trashPresetRootCache = type(raw) == "table" and raw or {}
    return trashPresetRootCache
end

function Data.GetTrashSpellPreset(mapID, npcID, spellID)
    local mid = tonumber(mapID)
    local nid = tonumber(npcID)
    local sid = tonumber(spellID)
    if not (mid and nid and sid) then
        return nil
    end
    local root = Data.GetTrashCDPresetRoot()
    local mapRow = type(root) == "table" and root[mid] or nil
    local mobRow = type(mapRow) == "table" and mapRow[nid] or nil
    local spellRow = type(mobRow) == "table" and mobRow[sid] or nil
    return type(spellRow) == "table" and spellRow or nil
end

function Data.GetEncounterMaps()
    local api = _G.EXBossData
    if type(api) ~= "table" or type(api.GetEncounterDataRoot) ~= "function" then
        return {}
    end
    local ok, data = pcall(api.GetEncounterDataRoot)
    if ok and type(data) == "table" then
        return data
    end
    return {}
end

local function BuildEncounterMapNameByInstanceID()
    local out = {}
    local data = Data.GetEncounterMaps()
    local maps = type(data.maps) == "table" and data.maps or data
    if type(maps) ~= "table" then
        return out
    end
    for key, row in pairs(maps) do
        if type(row) == "table" then
            local instanceID = tonumber(row.instanceID) or tonumber(row.instanceId) or tonumber(row.mapID) or
            tonumber(key)
            local mapName = tostring(row.mapName or row.name or "")
            if instanceID and instanceID > 0 and mapName ~= "" then
                out[instanceID] = mapName
            end
        end
    end
    return out
end

local function BuildEncounterMapNameByMapID()
    local out = {}
    local data = Data.GetEncounterMaps()
    local maps = type(data.maps) == "table" and data.maps or data
    if type(maps) ~= "table" then
        return out
    end
    for key, row in pairs(maps) do
        if type(row) == "table" then
            local mapID = tonumber(row.mapID) or tonumber(key)
            local mapName = tostring(row.mapName or row.name or "")
            if mapID and mapID > 0 and mapName ~= "" then
                out[mapID] = mapName
            end
        end
    end
    return out
end

local function BuildTrashMapIDByNameKey()
    local out = {}
    local root = Data.GetTrashCDDataRoot()
    for key, row in pairs(root) do
        if type(row) == "table" then
            local mapID = tonumber(row.mapID) or tonumber(key)
            local mapName = tostring(row.mapName or "")
            local nameKey = Data.NormalizeNameKey(mapName)
            if mapID and mapID > 0 and nameKey ~= "" then
                out[nameKey] = mapID
            end
        end
    end
    return out
end

function Data.GetEncounterMapNameByInstanceID()
    if not encounterMapNameByInstanceID then
        encounterMapNameByInstanceID = BuildEncounterMapNameByInstanceID()
    end
    return encounterMapNameByInstanceID
end

function Data.GetEncounterMapNameByMapID()
    if not encounterMapNameByMapID then
        encounterMapNameByMapID = BuildEncounterMapNameByMapID()
    end
    return encounterMapNameByMapID
end

function Data.GetTrashMapIDByNameKey()
    if not trashMapIDByNameKey then
        trashMapIDByNameKey = BuildTrashMapIDByNameKey()
    end
    return trashMapIDByNameKey
end

function Data.GetCurrentInstanceContext()
    local inInstance, instanceType = IsInInstance()
    if inInstance ~= true then
        return nil, nil, instanceType
    end

    local state = ExwindTools and ExwindTools.State or nil
    local instanceID = tonumber(state and state.InstanceID) or tonumber((select(8, GetInstanceInfo()))) or 0
    local mapID = tonumber(state and state.MapID) or 0
    local instanceName = tostring((select(1, GetInstanceInfo())) or "")
    local mapName = ""

    if mapID > 0 then
        mapName = tostring(Data.GetEncounterMapNameByMapID()[mapID] or "")
    end
    if instanceID > 0 and mapName == "" then
        mapName = tostring(Data.GetEncounterMapNameByInstanceID()[instanceID] or "")
    end
    if mapName == "" then
        mapName = instanceName
    end

    return instanceID > 0 and instanceID or nil, mapName, instanceType
end

function Data.GetSpellNameSafe(spellID)
    local sid = tonumber(spellID)
    if not sid then
        return nil
    end

    local CSpell = _G.C_Spell
    if type(CSpell) == "table" then
        if type(CSpell.GetSpellName) == "function" then
            local ok, name = pcall(CSpell.GetSpellName, sid)
            if ok and type(name) == "string" and name ~= "" then
                return name
            end
        end
        if type(CSpell.GetSpellInfo) == "function" then
            local ok, info = pcall(CSpell.GetSpellInfo, sid)
            if ok and type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
                return info.name
            end
        end
    end

    if type(_G.GetSpellInfo) == "function" then
        local ok, name = pcall(_G.GetSpellInfo, sid)
        if ok and type(name) == "string" and name ~= "" then
            return name
        end
    end

    return nil
end

function Data.GetSpellIconSafe(spellID)
    local sid = tonumber(spellID)
    if not sid then
        return nil
    end

    local CSpell = _G.C_Spell
    if type(CSpell) == "table" and type(CSpell.GetSpellInfo) == "function" then
        local ok, info = pcall(CSpell.GetSpellInfo, sid)
        if ok and type(info) == "table" and info.iconID then
            return info.iconID
        end
    end

    if type(_G.GetSpellInfo) == "function" then
        local ok, _, _, icon = pcall(_G.GetSpellInfo, sid)
        if ok and icon then
            return icon
        end
    end

    return nil
end

function Data.GetSpellDescriptionSafe(spellID)
    local sid = tonumber(spellID)
    if not sid then
        return nil
    end

    local CSpell = _G.C_Spell
    if type(CSpell) == "table" and type(CSpell.GetSpellDescription) == "function" then
        local ok, desc = pcall(CSpell.GetSpellDescription, sid)
        if ok and type(desc) == "string" and desc ~= "" then
            return desc
        end
    end

    return nil
end
