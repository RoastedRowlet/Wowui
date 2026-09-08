---@diagnostic disable: undefined-global
-- Configuration ownership: Factory -> Author -> CurrentUser -> scene Runtime.

local DATA_WTF_VERSION = 7
local EVENT_BLACKLIST = { [513] = true }

_G.EXBossData = _G.EXBossData or {}
local API = _G.EXBossData

local CurrentUsers = {}
local CurrentContexts = {}

local function Copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, child in pairs(value) do out[key] = Copy(child) end
    return out
end

local function Overlay(target, source)
    if type(source) ~= "table" then return end
    for key, value in pairs(source) do
        if type(value) == "table" then
            local child = type(target[key]) == "table" and target[key] or {}
            target[key] = child
            Overlay(child, value)
        else
            target[key] = value
        end
    end
end

local function Trim(value)
    local text = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
    return text ~= "" and text or nil
end

local function EnsureRoot()
    if type(EXBossDataDB) ~= "table" or EXBossDataDB.wtfVersion ~= DATA_WTF_VERSION then
        EXBossDataDB = {
            wtfVersion = DATA_WTF_VERSION,
            configuration = { mplus = { users = {} }, raid = { users = {} } },
            timer = { timelineMode = {} },
        }
    end
    local configuration = type(EXBossDataDB.configuration) == "table" and EXBossDataDB.configuration or {}
    EXBossDataDB.configuration = configuration
    for _, category in ipairs({ "mplus", "raid" }) do
        local bucket = type(configuration[category]) == "table" and configuration[category] or {}
        configuration[category] = bucket
        if type(bucket.users) ~= "table" then bucket.users = {} end
        if type(bucket.importedAuthors) ~= "table" then bucket.importedAuthors = {} end
    end
    if type(EXBossDataDB.timer) ~= "table" then EXBossDataDB.timer = {} end
    if type(EXBossDataDB.timer.timelineMode) ~= "table" then EXBossDataDB.timer.timelineMode = {} end
    return EXBossDataDB
end

local function Users(category)
    if category ~= "mplus" and category ~= "raid" then return nil end
    return EnsureRoot().configuration[category].users
end

local function ImportedAuthors(category)
    if category ~= "mplus" and category ~= "raid" then return nil end
    return EnsureRoot().configuration[category].importedAuthors
end

local function GetAuthor(category, authorID)
    local root = _G.EXBOSS_AUTHORS
    local authors = type(root) == "table" and root[category] or nil
    local id = Trim(authorID)
    local author = id and type(authors) == "table" and authors[id] or nil
    if type(author) ~= "table" and id then author = (ImportedAuthors(category) or {})[id] end
    return type(author) == "table" and author or nil
end

local function GetFactoryBase(category)
    local resolver = API.FactoryResolver
    if type(resolver) ~= "table" then return nil end
    if category == "mplus" and type(resolver.GetMplusBase) == "function" then
        return resolver.GetMplusBase(resolver.GetMplusFactoryID())
    end
    if category == "raid" and type(resolver.GetRaidBase) == "function" then
        return resolver.GetRaidBase(resolver.GetRaidFactoryID())
    end
    return nil
end

local function Runtime(category, create)
    if category ~= "mplus" and category ~= "raid" then return nil end
    _G.ExBoss = _G.ExBoss or {}
    local key = category == "mplus" and "RuntimeMplus" or "RuntimeRaid"
    local runtime = _G.ExBoss[key]
    if type(runtime) ~= "table" and create then
        runtime = {}
        _G.ExBoss[key] = runtime
    end
    return type(runtime) == "table" and runtime or nil
end

local function ReadPath(root, path)
    local node = root
    for _, key in ipairs(path or {}) do
        if type(node) ~= "table" then return nil end
        node = node[key]
    end
    return node
end

local function WritePath(root, path, value)
    if type(root) ~= "table" or type(path) ~= "table" or #path == 0 then return false end
    local node = root
    for index = 1, #path - 1 do
        local key = path[index]
        if key == nil then return false end
        if type(node[key]) ~= "table" then node[key] = {} end
        node = node[key]
    end
    local leaf = path[#path]
    if leaf == nil or value == nil then return false end
    node[leaf] = Copy(value)
    return true
end

local function Active(category, userID)
    local context = CurrentContexts[category]
    return context and context.userID == userID
end

-- This is the only Runtime rebuild path.  Inputs are copied, never mutated.
function API.RebuildRuntime(category, authorID, userID)
    category, authorID, userID = Trim(category), Trim(authorID), Trim(userID)
    local users = Users(category)
    local user = users and users[userID] or nil
    local author = GetAuthor(category, authorID)
    local factory = GetFactoryBase(category)
    if type(user) ~= "table" then return false, "current user configuration not found" end
    if not author then return false, "author configuration not found" end
    if type(factory) ~= "table" then return false, "factory configuration not found" end

    CurrentUsers[category] = user
    CurrentContexts[category] = { category = category, authorID = authorID, userID = userID }

    local runtime = Runtime(category, true)
    wipe(runtime)
    Overlay(runtime, factory)
    Overlay(runtime, author.values)
    Overlay(runtime, user)
    return true, runtime
end

function API.ActivateUserConfiguration(category, userID, authorID)
    return API.RebuildRuntime(category, authorID, userID)
end

function API.GetRuntime(category)
    return Runtime(Trim(category), false)
end

function API.GetCurrentUser(category)
    return CurrentUsers[Trim(category)]
end

function API.GetCurrentConfiguration(category)
    local context = CurrentContexts[Trim(category)]
    return context and Copy(context) or nil
end

function API.SetCurrentUserPath(category, path, value)
    category = Trim(category)
    local user = CurrentUsers[category]
    if type(user) ~= "table" then return false, "current user configuration unavailable" end
    if value == nil then return false, "nil cannot be saved as a user value" end
    if not WritePath(user, path, value) then return false, "invalid configuration path" end
    local runtime = Runtime(category, false)
    if not WritePath(runtime, path, value) then return false, "current Runtime unavailable" end
    return true
end

function API.GetCurrentRuntimePath(category, path)
    return ReadPath(Runtime(Trim(category), false), path)
end

function API.ListAuthors(category)
    local authors = type(_G.EXBOSS_AUTHORS) == "table" and _G.EXBOSS_AUTHORS[category] or nil
    local out, seen = {}, {}
    for id, author in pairs(type(authors) == "table" and authors or {}) do
        out[#out + 1] = { id = id, name = author.name, author = author.author, category = category }
        seen[id] = true
    end
    for id, author in pairs(ImportedAuthors(category) or {}) do
        if not seen[id] then
            out[#out + 1] = { id = id, name = author.name, author = author.author, category = category, imported = true }
        end
    end
    table.sort(out, function(left, right) return left.id < right.id end)
    return out
end

function API.ListMplusAuthors() return API.ListAuthors("mplus") end
function API.ListRaidAuthors() return API.ListAuthors("raid") end

-- Export is deliberately a copy. Authors remain read-only runtime artifacts;
-- sharing code may package their values with a player's explicit User values.
function API.ExportAuthorConfiguration(category, authorID)
    category, authorID = Trim(category), Trim(authorID)
    local author = GetAuthor(category, authorID)
    if not author or type(author.values) ~= "table" then
        return nil, "author configuration not found"
    end
    return {
        id = authorID,
        name = tostring(author.name or authorID),
        author = tostring(author.author or ""),
        values = Copy(author.values),
    }
end

function API.IsAuthorNameAvailable(category, requestedName, exceptID)
    category, exceptID = Trim(category), Trim(exceptID)
    local name = Trim(requestedName)
    if (category ~= "mplus" and category ~= "raid") or not name then return false end
    for _, row in ipairs(API.ListAuthors(category)) do
        if Trim(row.name) == name and Trim(row.id) ~= exceptID then
            return false
        end
    end
    return true
end

-- Imported strings are selectable Author artifacts. Their values are already
-- Author -> User merged by ImportExport, so they remain usable after reload
-- without creating a second selectable User configuration.
function API.ImportAuthorConfiguration(category, artifact)
    category = Trim(category)
    if (category ~= "mplus" and category ~= "raid") or type(artifact) ~= "table"
        or type(artifact.values) ~= "table" then
        return false, "invalid imported Author configuration"
    end
    local imported = ImportedAuthors(category)
    local index, id = 1, "imported-" .. category .. "-1"
    while imported[id] ~= nil or GetAuthor(category, id) ~= nil do
        index = index + 1
        id = "imported-" .. category .. "-" .. index
    end
    local name = Trim(artifact.name)
    if not name then return false, "Author name is required" end
    if not API.IsAuthorNameAvailable(category, name) then
        return false, "Author configuration name already exists"
    end
    imported[id] = {
        id = id,
        category = category,
        name = name,
        author = tostring(artifact.author or ""),
        imported = true,
        values = Copy(artifact.values),
    }
    return true, id
end

function API.RenameImportedAuthor(category, authorID, name)
    category, authorID = Trim(category), Trim(authorID)
    name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local imported = ImportedAuthors(category)
    local author = imported and imported[authorID] or nil
    if not author then return false, "imported Author configuration not found" end
    if name == "" then return false, "Author name is required" end
    if not API.IsAuthorNameAvailable(category, name, authorID) then
        return false, "Author configuration name already exists"
    end
    author.name = name
    return true
end

function API.DeleteImportedAuthor(category, authorID)
    category, authorID = Trim(category), Trim(authorID)
    local imported = ImportedAuthors(category)
    if not imported or type(imported[authorID]) ~= "table" then
        return false, "only imported Author configurations can be deleted"
    end
    imported[authorID] = nil
    return true
end

function API.ListUserConfigurations(category)
    local out = {}
    for id in pairs(Users(category) or {}) do out[#out + 1] = { id = id, category = category } end
    table.sort(out, function(left, right) return left.id < right.id end)
    return out
end

function API.ListMplusUserConfigurations() return API.ListUserConfigurations("mplus") end
function API.ListRaidUserConfigurations() return API.ListUserConfigurations("raid") end

function API.IsUserConfiguration(category, configID)
    local id = Trim(configID)
    return id ~= nil and type((Users(category) or {})[id]) == "table"
end

function API.IsMplusUserConfiguration(configID) return API.IsUserConfiguration("mplus", configID) end
function API.IsRaidUserConfiguration(configID) return API.IsUserConfiguration("raid", configID) end
function API.IsMplusConfiguration(configID) return API.IsMplusUserConfiguration(configID) end
function API.IsRaidConfiguration(configID) return API.IsRaidUserConfiguration(configID) end

function API.CreateUserConfiguration(category, configID, values)
    local id = Trim(configID)
    local users = Users(category)
    if not users or not id then return false, "invalid user configuration" end
    if users[id] ~= nil then return false, category .. " configuration id exists" end
    if values ~= nil and type(values) ~= "table" then return false, "invalid user configuration values" end
    users[id] = Copy(values or {})
    return true, id
end

function API.CreateMplusUserConfiguration(configID, values) return API.CreateUserConfiguration("mplus", configID, values) end
function API.CreateRaidUserConfiguration(configID, values) return API.CreateUserConfiguration("raid", configID, values) end

function API.ExportUserConfiguration(category, configID)
    local id = Trim(configID)
    local values = id and (Users(category) or {})[id] or nil
    if type(values) ~= "table" then return nil, "user configuration not found" end
    return Copy(values)
end

function API.ImportUserConfiguration(category, values)
    local users = Users(category)
    if not users or type(values) ~= "table" then return false, "invalid user configuration values" end
    local index = 1
    local configID = "imported-" .. category .. "-" .. index
    while users[configID] ~= nil do
        index = index + 1
        configID = "imported-" .. category .. "-" .. index
    end
    users[configID] = Copy(values)
    return true, configID
end

function API.CopyUserConfiguration(category, configID, sourceID)
    local target, source = Trim(configID), Trim(sourceID)
    local users = Users(category)
    if not users or not target or type(users[source]) ~= "table" then return false, "source user configuration not found" end
    if users[target] ~= nil then return false, category .. " configuration id exists" end
    users[target] = Copy(users[source])
    return true, target
end

function API.CopyMplusUserConfiguration(configID, sourceID) return API.CopyUserConfiguration("mplus", configID, sourceID) end
function API.CopyRaidUserConfiguration(configID, sourceID) return API.CopyUserConfiguration("raid", configID, sourceID) end

function API.DeleteUserConfiguration(category, configID)
    local id = Trim(configID)
    local users = Users(category)
    if not users or type(users[id]) ~= "table" then return false, "user configuration not found" end
    if Active(category, id) then return false, "current user configuration cannot be deleted" end
    users[id] = nil
    return true
end

function API.DeleteMplusUserConfiguration(configID) return API.DeleteUserConfiguration("mplus", configID) end
function API.DeleteRaidUserConfiguration(configID) return API.DeleteUserConfiguration("raid", configID) end

local function GetMplusDungeonAuraSoundRoot(configID, dungeonKey)
    if not Active("mplus", configID) then return nil end
    local runtime = Runtime("mplus", false)
    local row = type(runtime) == "table" and type(runtime.dungeonOptions) == "table" and runtime.dungeonOptions[dungeonKey] or nil
    local root = type(row) == "table" and row.auraSounds or nil
    local items = type(root) == "table" and root.items or nil
    return type(items) == "table" and root or nil
end

function API.GetMplusDungeonAuraSoundView(configID, dungeonKey)
    local root = GetMplusDungeonAuraSoundRoot(configID, dungeonKey)
    local items = type(root) == "table" and root.items or nil
    if type(items) ~= "table" then return nil end
    -- 只把当前 Runtime 的 action key 投影给列表；行数据仍由 ActionView
    -- 按需读取，不能把完整 auraSounds 根交给 UI 或 Runtime 长期持有。
    local actionIDs = {}
    for actionID, action in pairs(items) do
        if type(actionID) == "string" and actionID ~= "" and type(action) == "table" then
            actionIDs[#actionIDs + 1] = actionID
        end
    end
    table.sort(actionIDs)
    return {
        revision = root.version,
        actionIDs = actionIDs,
    }
end
function API.GetMplusDungeonAuraSoundActionView(configID, dungeonKey, actionID)
    local root = GetMplusDungeonAuraSoundRoot(configID, dungeonKey)
    return type(root) == "table" and type(root.items) == "table" and root.items[actionID] or nil
end

function API.SetMplusDungeonAuraSoundActionFields(configID, dungeonKey, actionID, fields)
    if not Active("mplus", configID) then return false, "target user configuration is not current" end
    actionID = Trim(actionID)
    local root = GetMplusDungeonAuraSoundRoot(configID, dungeonKey)
    if not actionID or type(root) ~= "table" or type(root.items[actionID]) ~= "table" then
        return false, "aura sound action not found"
    end
    if type(fields) ~= "table" or next(fields) == nil then return false, "no aura sound fields" end
    for field, value in pairs(fields) do
        if type(field) ~= "string" or field == "" or value == nil then return false, "invalid aura sound field" end
    end
    for field, value in pairs(fields) do
        local ok, reason = API.SetCurrentUserPath("mplus", { "dungeonOptions", dungeonKey, "auraSounds", "items", actionID, field }, value)
        if not ok then return false, reason end
    end
    return true
end

function API.CreateMplusDungeonAuraSoundAction(configID, dungeonKey, actionID, action)
    if not Active("mplus", configID) then return false, "target user configuration is not current" end
    actionID = Trim(actionID)
    local root = GetMplusDungeonAuraSoundRoot(configID, dungeonKey)
    if not actionID or type(dungeonKey) ~= "string" or dungeonKey == "" or type(action) ~= "table" then
        return false, "invalid aura sound action"
    end
    if type(root) == "table" and root.items[actionID] ~= nil then return false, "aura sound action exists" end
    return API.SetCurrentUserPath("mplus", { "dungeonOptions", dungeonKey, "auraSounds", "items", actionID }, action)
end

function API.GetTimelineModeDB()
    return EnsureRoot().timer.timelineMode
end

function API.IsEventBlacklisted(eventID)
    return EVENT_BLACKLIST[tonumber(eventID)] == true
end

local function GetEncounterMaps()
    local data = _G.EXBOSS_ENCOUNTER_DATA
    if type(data) ~= "table" then return nil end
    return type(data.maps) == "table" and data.maps or data
end

function API.GetEncounterDataRoot()
    return GetEncounterMaps() or {}
end

function API.GetFactoryEventDefaults(eventID)
    local resolver = API.FactoryResolver
    local factoryID = resolver and resolver.GetMplusFactoryID and resolver.GetMplusFactoryID() or nil
    if not resolver or not factoryID then return nil end
    if eventID == nil then return resolver.GetEventDefaults(factoryID) end
    return resolver.GetEventDefault(tonumber(eventID), factoryID)
end

local function BuildInterval(series)
    if type(series) ~= "table" then return nil end
    local out = {}
    for _, value in ipairs(series) do
        local number = tonumber(value)
        if number and number > 0 then out[#out + 1] = number end
    end
    return #out == 0 and nil or (#out == 1 and out[1] or out)
end

local function BuildTimelineSkill(eventID, event)
    if type(event) ~= "table" or API.IsEventBlacklisted(eventID) then return nil end
    local first = tonumber(event.firstSeenSec)
    if not first then return nil end
    local spellID = tonumber(event.spellID) or tonumber(event.evenSpellID)
    return {
        eventID = tonumber(event.eventID) or tonumber(eventID), spellID = spellID,
        evenSpellID = tonumber(event.evenSpellID), spellIdentifier = tonumber(event.evenSpellID) or spellID,
        displayName = event.eventName or event.name or tostring(eventID), source = "fixed", first = first,
        interval = BuildInterval(event.cdSeriesSec), preAlert = 5, castDuration = 1.5, barPriority = 2,
        showBunBar = true, showTimerBar = true, screenAlert = false, preAlertText = "{name}",
        voiceLabel = tostring(event.voiceLabel or event.eventName or event.name or eventID),
    }
end

function API.RebuildTimelineBosses()
    local maps = GetEncounterMaps()
    if type(maps) ~= "table" then return end
    _G.ExBoss = _G.ExBoss or {}
    _G.ExBoss.Timeline = _G.ExBoss.Timeline or {}
    _G.ExBoss.Timeline._bosses = {}
    for mapID, map in pairs(maps) do
        for bossID, boss in pairs(type(map) == "table" and map.bosses or {}) do
            local encounterID = tonumber(boss.encounterID) or tonumber(bossID)
            if encounterID then
                local skills = {}
                for eventID, event in pairs(type(boss.events) == "table" and boss.events or {}) do
                    local skill = BuildTimelineSkill(eventID, event)
                    if skill then skills[#skills + 1] = skill end
                end
                table.sort(skills, function(left, right) return left.first == right.first and left.eventID < right.eventID or left.first < right.first end)
                _G.ExBoss.Timeline._bosses[encounterID] = {
                    encounterID = encounterID, name = boss.bossName or boss.name or tostring(encounterID), mapID = tonumber(mapID),
                    axisType = ((_G.EXBOSS_FIXED_TIMELINE_ENCOUNTERS or {})[encounterID] and #skills > 0) and "fixed" or "blizzard",
                    skills = skills,
                }
            end
        end
    end
end

local function Bootstrap()
    EnsureRoot()
    -- EXBossData finishes loading after the Author artifacts in its TOC.  Make
    -- an empty default M+ User current here.  Raid Runtime remains absent until
    -- the player enters a raid or opens a raid configuration page.
    local users = Users("mplus")
    if type(users["default-mplus-dps"]) ~= "table" then users["default-mplus-dps"] = {} end
    if GetAuthor("mplus", "builtin-mplus-dps") then
        API.RebuildRuntime("mplus", "builtin-mplus-dps", "default-mplus-dps")
    end
    API.RebuildTimelineBosses()
end

do
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("ADDON_LOADED")
    frame:SetScript("OnEvent", function(self, _, addonName)
        if tostring(addonName or ""):lower() == "exbossdata" then
            Bootstrap()
            self:UnregisterEvent("ADDON_LOADED")
        end
    end)
end

Bootstrap()
