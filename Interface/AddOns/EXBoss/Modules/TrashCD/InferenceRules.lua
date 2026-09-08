---@diagnostic disable: undefined-global

ExBoss = ExBoss or {}
ExBoss.Trash = ExBoss.Trash or {}
ExBoss.TrashCD = ExBoss.TrashCD or {}

local Mod = ExBoss.TrashCD.InferenceRules or {}
ExBoss.TrashCD.InferenceRules = Mod
ExBoss.Trash.InferenceRules = Mod

local Data = ExBoss.TrashCD and ExBoss.TrashCD.Data or nil

Mod.layer1 = Mod.layer1 or {}
Mod.layer2 = Mod.layer2 or {}

local defaultLayer1 = {}
local defaultLayer2 = {}
local defaultsBuilt = false

local function EnsureMapBucket(root, mapID)
    mapID = tonumber(mapID)
    if not mapID then
        return nil
    end
    root[mapID] = type(root[mapID]) == "table" and root[mapID] or {}
    return root[mapID]
end

local function CloneRuleList(rows)
    if type(rows) ~= "table" then
        return {}
    end
    local out = {}
    for i = 1, #rows do
        local row = rows[i]
        if type(row) == "table" then
            out[#out + 1] = {
                kind = row.kind,
                duration = tonumber(row.duration),
                tolerance = tonumber(row.tolerance),
                first = tonumber(row.first),
            }
        end
    end
    return out
end

local function NormalizeOptionalBoolean(value)
    if type(value) == "boolean" then
        return value
    end
    return nil
end

local function NormalizeLayer1Rule(rule)
    rule = type(rule) == "table" and rule or {}
    return {
        level = rule.level,
        power = rule.power,
        nonElite = rule.nonElite == true,
        isLieutenant = NormalizeOptionalBoolean(rule.isLieutenant),
        hasCreatureFamily = NormalizeOptionalBoolean(rule.hasCreatureFamily),
        coPresenceNPCIDs = type(rule.coPresenceNPCIDs) == "table" and rule.coPresenceNPCIDs or nil,
        hasCastSpell = rule.hasCastSpell == true,
        hasChannelSpell = rule.hasChannelSpell == true,
        cannotInterrupt = rule.cannotInterrupt == true,
        bossStages = tostring(rule.bossStages or rule.bossStage or rule.boss or ""),
    }
end

local function NormalizeLayer2Rule(rule)
    rule = type(rule) == "table" and rule or {}
    return {
        castRules = CloneRuleList(rule.castRules),
        channelRules = CloneRuleList(rule.channelRules),
        firstCastRules = CloneRuleList(rule.firstCastRules),
        preCombatChanneling = rule.preCombatChanneling == true,
        noObservedCastExpected = rule.noObservedCastExpected == true,
        canCastSuccess = rule.canCastSuccess == true,
        canCastInterrupt = rule.canCastInterrupt == true,
        canChannelSuccess = rule.canChannelSuccess == true,
        canCastIntoChannel = rule.canCastIntoChannel == true,
    }
end

local function ParseDurationSet(raw)
    if type(raw) ~= "string" or raw == "" then
        return {}
    end
    local out = {}
    for token in raw:gmatch("[0-9%.]+") do
        local value = tonumber(token)
        if value and value > 0 then
            out[#out + 1] = value
        end
    end
    return out
end

local function AppendDurationValues(out, value)
    if type(out) ~= "table" then
        return
    end
    if type(value) == "table" then
        for _, item in pairs(value) do
            AppendDurationValues(out, item)
        end
        return
    end
    if type(value) == "string" then
        for item in string.gmatch(value, "[^,;/|%s]+") do
            AppendDurationValues(out, item)
        end
        return
    end
    local n = tonumber(value)
    if n and n > 0 then
        for i = 1, #out do
            if math.abs(out[i] - n) <= 0.001 then
                return
            end
        end
        out[#out + 1] = n
    end
end

local function GetCastTimeCandidates(spellData)
    local out = {}
    if type(spellData) ~= "table" then
        return out
    end
    AppendDurationValues(out, spellData.castTime)
    AppendDurationValues(out, spellData.castTimeExtra)
    return out
end

local function GetChannelTimeCandidates(spellData)
    local out = {}
    if type(spellData) ~= "table" then
        return out
    end
    AppendDurationValues(out, spellData.channelTime)
    AppendDurationValues(out, spellData.channelDuration)
    AppendDurationValues(out, spellData.channelTimeSet)
    return out
end

local function AppendRuleDuration(list, kind, duration, tolerance, first)
    if type(list) ~= "table" then
        return
    end
    duration = tonumber(duration)
    if not duration or duration <= 0 then
        return
    end
    for i = 1, #list do
        local row = list[i]
        if type(row) == "table"
            and tostring(row.kind or "") == tostring(kind or "")
            and tonumber(row.duration) == duration
            and (first == nil or tonumber(row.first) == tonumber(first))
        then
            return
        end
    end
    list[#list + 1] = {
        kind = kind,
        duration = duration,
        tolerance = tolerance,
        first = first,
    }
end

local function UnpackRow(row)
    ---@diagnostic disable-next-line: undefined-field
    local _fn = _G.EXDB and _G.EXDB._r
    if type(row) ~= "table" or row[1] == nil or type(_fn) ~= "function" then
        return row
    end
    local t = _fn(row[1])
    if type(t) ~= "table" then
        return row
    end
    t.dungeon        = row[2]
    t.npcID          = row[3]
    t.name           = row[4]
    t.boss           = row[5]
    t.castTimeSet    = row[6]
    t.channelTimeSet = row[7]
    t.spellIDs       = row[8]
    return t
end

local function BuildDefaultLayer1()
    local out = {}
    local traitsRoot = Data and Data.GetTrashMobTraitsRoot and Data.GetTrashMobTraitsRoot() or nil
    local rows = type(traitsRoot) == "table" and type(traitsRoot.rows) == "table" and traitsRoot.rows or {}
    local mapByNameKey = Data and Data.GetTrashMapIDByNameKey and Data.GetTrashMapIDByNameKey() or {}
    local normalize = Data and Data.NormalizeNameKey or tostring
    for i = 1, #rows do
        local row = rows[i]
        if type(row) == "table" then
            local t = UnpackRow(row)
            local mapID = type(mapByNameKey) == "table" and mapByNameKey[normalize(t.dungeon)] or nil
            local npcID = tonumber(t.npcID)
            if mapID and npcID then
                out[mapID] = type(out[mapID]) == "table" and out[mapID] or {}
                out[mapID][npcID] = NormalizeLayer1Rule(t)
            end
        end
    end
    return out
end

local function BuildDefaultLayer2()
    local out = {}
    local traitsRoot = Data and Data.GetTrashMobTraitsRoot and Data.GetTrashMobTraitsRoot() or nil
    local traitRows = type(traitsRoot) == "table" and type(traitsRoot.rows) == "table" and traitsRoot.rows or {}
    local mapByNameKey = Data and Data.GetTrashMapIDByNameKey and Data.GetTrashMapIDByNameKey() or {}
    local normalize = Data and Data.NormalizeNameKey or tostring
    for i = 1, #traitRows do
        local row = traitRows[i]
        if type(row) == "table" then
            local t = UnpackRow(row)
            local mapID = type(mapByNameKey) == "table" and mapByNameKey[normalize(t.dungeon)] or nil
            local npcID = tonumber(t.npcID)
            if mapID and npcID then
                out[mapID] = type(out[mapID]) == "table" and out[mapID] or {}
                local entry = out[mapID][npcID]
                if type(entry) ~= "table" then
                    entry = NormalizeLayer2Rule({})
                    out[mapID][npcID] = entry
                end
                local castSet = ParseDurationSet(t.castTimeSet)
                for j = 1, #castSet do
                    AppendRuleDuration(entry.castRules, "cast", castSet[j], 0.20, nil)
                end
                local channelSet = ParseDurationSet(t.channelTimeSet)
                for j = 1, #channelSet do
                    AppendRuleDuration(entry.channelRules, "channel", channelSet[j], 0.20, nil)
                end
                if t.preCombatChanneling == true then
                    entry.preCombatChanneling = true
                end
                if t.noCastSkill == true and t.hasCastSpell ~= true and t.hasChannelSpell ~= true then
                    entry.noObservedCastExpected = true
                end
                if t.hasCastSpell == true then
                    entry.canCastSuccess = true
                    if t.cannotInterrupt ~= true then
                        entry.canCastInterrupt = true
                    end
                end
                if t.hasChannelSpell == true then
                    entry.canChannelSuccess = true
                end
                if t.hasCastSpell == true and t.hasChannelSpell == true then
                    entry.canCastIntoChannel = true
                end
            end
        end
    end

    local cdRoot = Data and Data.GetTrashCDDataRoot and Data.GetTrashCDDataRoot() or nil
    if type(cdRoot) == "table" then
        for mapKey, mapRow in pairs(cdRoot) do
            local mapID = tonumber(type(mapRow) == "table" and mapRow.mapID or mapKey)
            local mobs = type(mapRow) == "table" and type(mapRow.mobs) == "table" and mapRow.mobs or nil
            if mapID and type(mobs) == "table" then
                out[mapID] = type(out[mapID]) == "table" and out[mapID] or {}
                for npcKey, mobRow in pairs(mobs) do
                    local npcID = tonumber(type(mobRow) == "table" and mobRow.npcID or npcKey)
                    local spells = type(mobRow) == "table" and type(mobRow.spells) == "table" and mobRow.spells or nil
                    if npcID and type(spells) == "table" then
                        local entry = out[mapID][npcID]
                        if type(entry) ~= "table" then
                            entry = NormalizeLayer2Rule({})
                            out[mapID][npcID] = entry
                        end
                        for _, spellRow in pairs(spells) do
                            if type(spellRow) == "table" then
                                local first = tonumber(spellRow.first)
                                local castTimes = GetCastTimeCandidates(spellRow)
                                local channelTimes = GetChannelTimeCandidates(spellRow)
                                if #castTimes > 0 then
                                    for castIndex = 1, #castTimes do
                                        local castTime = castTimes[castIndex]
                                        AppendRuleDuration(entry.castRules, "cast", castTime, 0.20, nil)
                                        if first and first > 0 then
                                            AppendRuleDuration(entry.firstCastRules, "cast", castTime, 2.0, first)
                                        end
                                    end
                                    entry.canCastSuccess = true
                                    if entry.canCastInterrupt ~= true then
                                        entry.canCastInterrupt = true
                                    end
                                end
                                if #channelTimes > 0 then
                                    for channelIndex = 1, #channelTimes do
                                        AppendRuleDuration(entry.channelRules, "channel", channelTimes[channelIndex], 0.20, nil)
                                    end
                                    entry.canChannelSuccess = true
                                end
                                if #castTimes > 0 and #channelTimes > 0 then
                                    entry.canCastIntoChannel = true
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return out
end

local function EnsureDefaults()
    if defaultsBuilt == true then
        return
    end
    defaultLayer1 = BuildDefaultLayer1()
    defaultLayer2 = BuildDefaultLayer2()
    defaultsBuilt = true
end

function Mod.GetLayer1Rule(mapID, npcID)
    EnsureDefaults()
    local mapRow = type(Mod.layer1) == "table" and Mod.layer1[tonumber(mapID)] or nil
    local npcRow = type(mapRow) == "table" and mapRow[tonumber(npcID)] or nil
    if type(npcRow) ~= "table" then
        mapRow = type(defaultLayer1) == "table" and defaultLayer1[tonumber(mapID)] or nil
        npcRow = type(mapRow) == "table" and mapRow[tonumber(npcID)] or nil
    end
    return type(npcRow) == "table" and npcRow or nil
end

function Mod.GetLayer2Rule(mapID, npcID)
    EnsureDefaults()
    local mapRow = type(Mod.layer2) == "table" and Mod.layer2[tonumber(mapID)] or nil
    local npcRow = type(mapRow) == "table" and mapRow[tonumber(npcID)] or nil
    if type(npcRow) ~= "table" then
        mapRow = type(defaultLayer2) == "table" and defaultLayer2[tonumber(mapID)] or nil
        npcRow = type(mapRow) == "table" and mapRow[tonumber(npcID)] or nil
    end
    return type(npcRow) == "table" and npcRow or nil
end

function Mod.SetLayer1Rule(mapID, npcID, rule)
    local mapRow = EnsureMapBucket(Mod.layer1, mapID)
    npcID = tonumber(npcID)
    if not mapRow or not npcID then
        return false
    end
    mapRow[npcID] = NormalizeLayer1Rule(rule)
    return true
end

function Mod.SetLayer2Rule(mapID, npcID, rule)
    local mapRow = EnsureMapBucket(Mod.layer2, mapID)
    npcID = tonumber(npcID)
    if not mapRow or not npcID then
        return false
    end
    mapRow[npcID] = NormalizeLayer2Rule(rule)
    return true
end

function Mod.ClearLayer1Rule(mapID, npcID)
    local mapRow = type(Mod.layer1) == "table" and Mod.layer1[tonumber(mapID)] or nil
    npcID = tonumber(npcID)
    if type(mapRow) == "table" and npcID then
        mapRow[npcID] = nil
    end
end

function Mod.ClearLayer2Rule(mapID, npcID)
    local mapRow = type(Mod.layer2) == "table" and Mod.layer2[tonumber(mapID)] or nil
    npcID = tonumber(npcID)
    if type(mapRow) == "table" and npcID then
        mapRow[npcID] = nil
    end
end

function Mod.Reset()
    Mod.layer1 = {}
    Mod.layer2 = {}
    defaultLayer1 = {}
    defaultLayer2 = {}
    defaultsBuilt = false
end

function Mod.RebuildDefaults()
    defaultLayer1 = {}
    defaultLayer2 = {}
    defaultsBuilt = false
    EnsureDefaults()
end
