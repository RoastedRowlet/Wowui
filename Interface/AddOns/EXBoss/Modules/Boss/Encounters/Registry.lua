---@diagnostic disable: undefined-global

ExBoss = ExBoss or {}
ExBoss.BossEncounters = ExBoss.BossEncounters or {}

local Registry = ExBoss.BossEncounters

Registry.byEncounterID = Registry.byEncounterID or {}
Registry.order = Registry.order or {}

local function CopyWithFactoryDefault(option, default)
    local out = {}
    for key, value in pairs(option) do out[key] = value end
    out.default = default
    return out
end

local function GetFactoryDungeonDefault(dungeonKey, optionKey)
    local resolver = _G.EXBossData and _G.EXBossData.FactoryResolver
    local factoryID = type(resolver) == "table" and type(resolver.GetMplusFactoryID) == "function"
        and resolver.GetMplusFactoryID() or nil
    local defaults = type(factoryID) == "string" and type(resolver.GetDungeonOptionDefaults) == "function"
        and resolver.GetDungeonOptionDefaults(factoryID) or nil
    local row = type(defaults) == "table" and defaults[tostring(dungeonKey or "")] or nil
    return type(row) == "table" and row[optionKey] or nil
end

local function GetFactoryEncounterDefaults(encounterID)
    local resolver = _G.EXBossData and _G.EXBossData.FactoryResolver
    local factoryID = type(resolver) == "table" and type(resolver.GetMplusFactoryID) == "function"
        and resolver.GetMplusFactoryID() or nil
    local defaults = type(factoryID) == "string" and type(resolver.GetEncounterOptionDefaults) == "function"
        and resolver.GetEncounterOptionDefaults(factoryID) or nil
    local row = type(defaults) == "table" and defaults[tonumber(encounterID)] or nil
    return type(row) == "table" and row or nil
end

function Registry:Register(def)
    if type(def) ~= "table" then
        return false
    end

    local encounterID = tonumber(def.encounterID)
    if not encounterID then
        return false
    end

    def.encounterID = encounterID
    if not self.byEncounterID[encounterID] then
        self.order[#self.order + 1] = encounterID
    end
    self.byEncounterID[encounterID] = def
    return true
end

function Registry:Get(encounterID)
    return self.byEncounterID[tonumber(encounterID)]
end

function Registry:GetAll()
    return self.byEncounterID
end

function Registry:GetDungeonOptions(dungeonKey)
    local key = tostring(dungeonKey or "")
    if key == "" then
        return {}, nil
    end

    local out = {}
    local seen = {}
    for i = 1, #self.order do
        local def = self.byEncounterID[self.order[i]]
        local dungeon = type(def) == "table" and def.dungeon or nil
        if type(dungeon) == "table" and tostring(dungeon.key or "") == key then
            local options = def.dungeonOptions
            if type(options) == "table" then
                for j = 1, #options do
                    local option = options[j]
                    local optionKey = type(option) == "table" and tostring(option.key or "") or ""
                    if optionKey ~= "" and not seen[optionKey] then
                        seen[optionKey] = true
                        -- The Factory is the only default-value truth.  This
                        -- registry owns display/layout metadata only.
                        out[#out + 1] = CopyWithFactoryDefault(option, GetFactoryDungeonDefault(key, optionKey))
                    end
                end
            end
        end
    end
    return out, key
end

function Registry:GetDungeonOptionsForEncounter(encounterID)
    local def = self:Get(encounterID)
    local dungeon = type(def) == "table" and def.dungeon or nil
    local dungeonKey = type(dungeon) == "table" and dungeon.key or nil
    local options = self:GetDungeonOptions(dungeonKey)
    return options, dungeonKey
end

-- 首领专属通用设置：布局与默认值由各 encounter 文件声明，
-- 不与副本级 dungeonOptions 混用。
function Registry:GetBossSettings(encounterID)
    local def = self:Get(encounterID)
    local settings = type(def) == "table" and def.bossSettings or nil
    if type(settings) ~= "table" then return nil end
    local out = {}
    for key, value in pairs(settings) do out[key] = value end
    out.defaults = GetFactoryEncounterDefaults(encounterID) or {}
    return out
end
