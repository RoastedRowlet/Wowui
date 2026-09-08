---@diagnostic disable: undefined-global

ExBoss = ExBoss or {}
ExBoss.Trash = ExBoss.Trash or {}
ExBoss.TrashCD = ExBoss.TrashCD or {}

local Mod = ExBoss.TrashCD.VoiceBlacklist or {}
ExBoss.TrashCD.VoiceBlacklist = Mod
ExBoss.Trash.VoiceBlacklist = Mod

local ENTRIES = {}

local function MakeKey(mapID, npcID, spellID)
    local map = tonumber(mapID)
    local npc = tonumber(npcID)
    local spell = tonumber(spellID)
    if not (map and npc and spell) then
        return nil
    end
    return string.format("%d:%d:%d", map, npc, spell)
end

function Mod.GetEntry(mapID, npcID, spellID)
    local key = MakeKey(mapID, npcID, spellID)
    if not key then
        return nil
    end
    local row = ENTRIES[key]
    if type(row) ~= "table" then
        return nil
    end
    return row
end

function Mod.IsDisabled(mapID, npcID, spellID)
    return Mod.GetEntry(mapID, npcID, spellID) ~= nil
end
