---@diagnostic disable: undefined-global
-- Read-only Factory lookup.  Runtime composition belongs exclusively to Store.

_G.EXBossData = _G.EXBossData or {}

local Resolver = {}
_G.EXBossData.FactoryResolver = Resolver

local function FindFactory(category)
    local factories = type(_G.EXBOSS_CONFIG_FACTORY) == "table" and _G.EXBOSS_CONFIG_FACTORY.factories or nil
    if type(factories) ~= "table" then return nil end
    local foundID, found
    for id, factory in pairs(factories) do
        if type(factory) == "table" and factory.category == category then
            if found ~= nil then return nil end
            foundID, found = id, factory
        end
    end
    if type(foundID) ~= "string" or foundID == "" or type(found) ~= "table" or found.id ~= foundID
        or type(found.base) ~= "table" then
        return nil
    end
    return found
end

function Resolver.GetMplusFactoryID()
    local factory = FindFactory("mplus")
    return factory and factory.id or nil
end

function Resolver.GetRaidFactoryID()
    local factory = FindFactory("raid")
    return factory and factory.id or nil
end

function Resolver.GetFactory(factoryID)
    local factory = FindFactory("mplus")
    if factory and factory.id == factoryID then return factory end
    factory = FindFactory("raid")
    return factory and factory.id == factoryID and factory or nil
end

function Resolver.GetMplusFactory(factoryID)
    local factory = FindFactory("mplus")
    return factory and (factoryID == nil or factory.id == factoryID) and factory or nil
end

function Resolver.GetRaidFactory(factoryID)
    local factory = FindFactory("raid")
    return factory and (factoryID == nil or factory.id == factoryID) and factory or nil
end

function Resolver.IsMplusFactory(factoryID)
    local factory = FindFactory("mplus")
    return factory ~= nil and factory.id == factoryID
end

function Resolver.IsRaidFactory(factoryID)
    local factory = FindFactory("raid")
    return factory ~= nil and factory.id == factoryID
end

function Resolver.GetMplusBase(factoryID)
    local factory = Resolver.GetMplusFactory(factoryID)
    return factory and factory.base or nil
end

function Resolver.GetRaidBase(factoryID)
    local factory = Resolver.GetRaidFactory(factoryID)
    return factory and factory.base or nil
end

function Resolver.GetEventDefaults(factoryID)
    local base = Resolver.GetMplusBase(factoryID)
    return type(base) == "table" and base.events or nil
end

function Resolver.GetEventDefault(eventID, factoryID)
    local events = Resolver.GetEventDefaults(factoryID)
    return type(events) == "table" and events[tonumber(eventID)] or nil
end

function Resolver.GetRaidEventDefaults(factoryID)
    local base = Resolver.GetRaidBase(factoryID)
    return type(base) == "table" and base.events or nil
end

function Resolver.GetRaidEventDefault(eventID, factoryID)
    local events = Resolver.GetRaidEventDefaults(factoryID)
    return type(events) == "table" and events[tonumber(eventID)] or nil
end

function Resolver.GetTrashCDDefaults(factoryID)
    local base = Resolver.GetMplusBase(factoryID)
    return type(base) == "table" and base.trashCD or nil
end

function Resolver.GetDungeonOptionDefaults(factoryID)
    local base = Resolver.GetMplusBase(factoryID)
    return type(base) == "table" and base.dungeonOptions or nil
end

function Resolver.GetEncounterOptionDefaults(factoryID)
    local base = Resolver.GetMplusBase(factoryID)
    return type(base) == "table" and base.encounterOptions or nil
end

function Resolver.GetTrashSpellDefault(mapID, npcID, spellID, factoryID)
    local defaults = Resolver.GetTrashCDDefaults(factoryID)
    local key = table.concat({ tostring(tonumber(mapID) or ""), tostring(tonumber(npcID) or ""), tostring(tonumber(spellID) or "") }, ":")
    return type(defaults) == "table" and type(defaults.spellEntries) == "table" and defaults.spellEntries[key] or nil
end
