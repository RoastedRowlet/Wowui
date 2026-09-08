---@diagnostic disable: undefined-global

-- A slot selects an Author.  Each Author owns exactly one private User override
-- table per scene.  The User table is an implementation detail: it never appears
-- as an independently selectable profile, and therefore can never be attached to
-- an unrelated Author by the settings UI.

ExBoss = ExBoss or {}
ExBoss.Modules = ExBoss.Modules or {}
ExBoss.Modules.Boss = ExBoss.Modules.Boss or {}

local BossConfig = ExBoss.Modules.Boss
local L = ExBoss.L or setmetatable({}, { __index = function(_, key) return key end })
ExBoss.BossConfig = BossConfig

local SCHEMA = 7
local SLOTS = {
    mplus_tank = { role = "tank", label = "大米坦克", author = "builtin-mplus-tank" },
    mplus_dps = { role = "dps", label = "大米DPS", author = "builtin-mplus-dps" },
    mplus_heal = { role = "heal", label = "大米治疗", author = "builtin-mplus-heal" },
    raid_tank = { role = "tank", label = "团本坦克", author = "builtin-raid-tank" },
    raid_dps = { role = "dps", label = "团本DPS", author = "builtin-raid-dps" },
    raid_heal = { role = "heal", label = "团本治疗", author = "builtin-raid-heal" },
}
local SLOT_ORDER = { "mplus_tank", "mplus_dps", "mplus_heal", "raid_tank", "raid_dps", "raid_heal" }

local function Trim(value)
    local text = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
    return text ~= "" and text or nil
end

local function NormalizeRole(role)
    role = tostring(role or ""):lower()
    if role == "tank" then return "tank" end
    if role == "heal" or role == "healer" then return "heal" end
    return "dps"
end

local function NormalizeSlot(slot)
    slot = tostring(slot or ""):lower()
    return SLOTS[slot] and slot or nil
end

local function SlotCategory(slot)
    return tostring(slot or ""):match("^(mplus)_") or tostring(slot or ""):match("^(raid)_")
end

local function CurrentRole()
    return NormalizeRole(ExwindTools and ExwindTools.State and ExwindTools.State.RoleKey)
end

local function CurrentSpecID()
    local id = tonumber(ExwindTools and ExwindTools.State and ExwindTools.State.SpecID)
    if not id and type(GetSpecialization) == "function" and type(GetSpecializationInfo) == "function" then
        local index = GetSpecialization()
        id = index and tonumber(GetSpecializationInfo(index)) or nil
    end
    return id and id > 0 and id or nil
end

local function API()
    local api = _G.EXBossData
    return type(api) == "table" and type(api.RebuildRuntime) == "function" and api or nil
end

local function IsBossDB(value)
    -- Selection data is local UI state.  Adding a field must never discard
    -- existing User configuration names or selections.
    return type(value) == "table" and type(value.selection) == "table"
        and type(value.names) == "table" and type(value.specSelection) == "table"
end

local function NewBossDB()
    return {
        schema = SCHEMA,
        selection = {}, names = {}, specSelection = {},
        -- selection/specSelection are retained as immutable migration history.
        -- New code reads only Author selection plus this Author -> User binding.
        authorSelection = {},
        specAuthorSelection = {},
        userByAuthor = { mplus = {}, raid = {} },
        activeSlot = "mplus_dps",
    }
end

local function DefaultUserID(slot)
    return "default-" .. tostring(slot)
end

local function IsValidUser(category, userID)
    local api = API()
    return category == "raid" and api and api.IsRaidUserConfiguration(userID) == true
        or category == "mplus" and api and api.IsMplusUserConfiguration(userID) == true
end

local function EnsureLegacyUser(slot)
    local api = API()
    local category = SlotCategory(slot)
    local id = DefaultUserID(slot)
    if not api or not category then return nil end
    local exists = category == "raid" and api.IsRaidUserConfiguration(id) or api.IsMplusUserConfiguration(id)
    if not exists then
        local create = category == "raid" and api.CreateRaidUserConfiguration or api.CreateMplusUserConfiguration
        local ok = create and create(id, {})
        if not ok then return nil end
    end
    return id
end

local function AuthorExists(category, authorID)
    local api = API()
    for _, row in ipairs(api and api.ListAuthors and api.ListAuthors(category) or {}) do
        if row.id == authorID then return true end
    end
    return false
end

local function MakeIndependentUser(category, sourceID)
    local api = API()
    if not api or type(api.ImportUserConfiguration) ~= "function" then
        return nil, "user configuration import unavailable"
    end
    local values = {}
    if sourceID then
        if type(api.ExportUserConfiguration) ~= "function" then
            return nil, "user configuration export unavailable"
        end
        local reason
        values, reason = api.ExportUserConfiguration(category, sourceID)
        if type(values) ~= "table" then return nil, reason or "user configuration not found" end
    end
    local ok, idOrReason = api.ImportUserConfiguration(category, values)
    if not ok then return nil, idOrReason end
    return idOrReason
end

local function EnsureBoundUser(db, category, authorID)
    if not (db and (category == "mplus" or category == "raid") and AuthorExists(category, authorID)) then
        return nil, "Author configuration not found"
    end
    db.userByAuthor = type(db.userByAuthor) == "table" and db.userByAuthor or {}
    db.userByAuthor[category] = type(db.userByAuthor[category]) == "table" and db.userByAuthor[category] or {}
    local bound = db.userByAuthor[category]
    if IsValidUser(category, bound[authorID]) then return bound[authorID] end
    local userID, reason = MakeIndependentUser(category)
    if not userID then return nil, reason end
    bound[authorID] = userID
    return userID
end

local function CloneAuthorForLegacyBinding(category, authorID)
    local api = API()
    if not api or type(api.ExportAuthorConfiguration) ~= "function" or type(api.ImportAuthorConfiguration) ~= "function" then
        return nil, "Author configuration import unavailable"
    end
    local artifact, reason = api.ExportAuthorConfiguration(category, authorID)
    if type(artifact) ~= "table" then return nil, reason or "Author configuration not found" end
    local ok, idOrReason = api.ImportAuthorConfiguration(category, {
        name = tostring(artifact.name or authorID) .. " (" .. L["保留的用户覆盖"] .. ")",
        author = artifact.author,
        values = artifact.values,
    })
    if not ok then return nil, idOrReason end
    return idOrReason
end

-- Schema 5 stored User selection and Author selection independently.  Convert
-- every old effective pair into an Author-bound pair without deleting a single
-- User table.  If the old model used one Author with different Users, clone the
-- Author artifact for the later assignment; if it reused one User with different
-- Authors, clone that User override.  Both cases retain the prior effective data.
local function MigrateToAuthorBoundUsers(db, oldSchema)
    db.authorSelection = type(db.authorSelection) == "table" and db.authorSelection or {}
    db.userByAuthor = type(db.userByAuthor) == "table" and db.userByAuthor or {}
    for _, category in ipairs({ "mplus", "raid" }) do
        db.userByAuthor[category] = type(db.userByAuthor[category]) == "table" and db.userByAuthor[category] or {}
    end
    -- Schema 6 already completed this Author -> bound User migration.  Schema
    -- 7 changes only where the active Author selection is stored.
    if oldSchema >= 6 then return end

    local owners = { mplus = {}, raid = {} }
    local legacyPairs = { mplus = {}, raid = {} }
    for _, category in ipairs({ "mplus", "raid" }) do
        for authorID, userID in pairs(db.userByAuthor[category]) do
            if IsValidUser(category, userID) then owners[category][userID] = authorID end
        end
    end

    local function BindContext(category, slot, specKey, authorID, userID)
        if not AuthorExists(category, authorID) then authorID = SLOTS[slot].author end
        if not IsValidUser(category, userID) then userID = EnsureLegacyUser(slot) end
        if not (authorID and userID) then return end

        local sourceAuthorID, sourceUserID = authorID, userID
        local prior = legacyPairs[category][sourceAuthorID]
        local mappedAuthorID = prior and prior[sourceUserID] or nil
        if mappedAuthorID then
            if specKey then
                db.specAuthorSelection[specKey] = type(db.specAuthorSelection[specKey]) == "table" and db.specAuthorSelection[specKey] or {}
                db.specAuthorSelection[specKey][slot] = mappedAuthorID
            else
                db.authorSelection[slot] = mappedAuthorID
            end
            return
        end

        local bindings, current = db.userByAuthor[category], db.userByAuthor[category][authorID]
        if IsValidUser(category, current) and current ~= userID then
            local cloneID = CloneAuthorForLegacyBinding(category, authorID)
            if cloneID then
                authorID = cloneID
                if specKey then
                    db.specAuthorSelection[specKey] = type(db.specAuthorSelection[specKey]) == "table" and db.specAuthorSelection[specKey] or {}
                    db.specAuthorSelection[specKey][slot] = cloneID
                else
                    db.authorSelection[slot] = cloneID
                end
            else
                -- Keep the first binding active if an unusually early load makes
                -- cloning impossible.  The original User table is still retained.
                return
            end
        end

        local owner = owners[category][userID]
        if owner and owner ~= authorID then
            local copied = MakeIndependentUser(category, userID)
            if copied then userID = copied else return end
        end
        bindings[authorID] = userID
        owners[category][userID] = authorID
        legacyPairs[category][sourceAuthorID] = legacyPairs[category][sourceAuthorID] or {}
        legacyPairs[category][sourceAuthorID][sourceUserID] = authorID
    end

    -- Base entries were always paired with the builtin Author in schema 5.
    for _, slot in ipairs(SLOT_ORDER) do
        local category = SlotCategory(slot)
        local authorID = db.authorSelection[slot]
        if not AuthorExists(category, authorID) then authorID = SLOTS[slot].author end
        db.authorSelection[slot] = authorID
        BindContext(category, slot, nil, authorID, db.selection[slot])
    end

    local specKeys, seenSpecKeys = {}, {}
    for rawSpecKey in pairs(db.specSelection) do
        local specKey = tostring(rawSpecKey)
        if not seenSpecKeys[specKey] then specKeys[#specKeys + 1], seenSpecKeys[specKey] = specKey, true end
    end
    for rawSpecKey in pairs(db.specAuthorSelection) do
        local specKey = tostring(rawSpecKey)
        if not seenSpecKeys[specKey] then specKeys[#specKeys + 1], seenSpecKeys[specKey] = specKey, true end
    end
    table.sort(specKeys)
    for _, specKey in ipairs(specKeys) do
        local selections = db.specSelection[specKey]
        local authorSelections = db.specAuthorSelection[specKey]
        if type(selections) == "table" or type(authorSelections) == "table" then
            for _, slot in ipairs(SLOT_ORDER) do
                local userID = type(selections) == "table" and selections[slot] or nil
                local hasAuthorSelection = type(authorSelections) == "table" and authorSelections[slot] ~= nil
                if userID ~= nil or hasAuthorSelection then
                    local category = SlotCategory(slot)
                    local authorID = hasAuthorSelection and authorSelections[slot] or nil
                    if not AuthorExists(category, authorID) then authorID = SLOTS[slot].author end
                    db.specAuthorSelection[specKey] = type(db.specAuthorSelection[specKey]) == "table" and db.specAuthorSelection[specKey] or {}
                    db.specAuthorSelection[specKey][slot] = authorID
                    BindContext(category, slot, specKey, authorID, userID or db.selection[slot])
                end
            end
        end
    end
end

-- Schema 6 accidentally made the active Author choice per-specialization.
-- There must instead be exactly one account-wide choice per role slot.  Keep
-- all old tables intact for safety, but capture the currently effective choice
-- once so an upgrade retains what the player was using at that moment.
local function MigrateToAccountWideAuthorSelection(db, oldSchema)
    if oldSchema >= SCHEMA then return end
    db.authorSelection = type(db.authorSelection) == "table" and db.authorSelection or {}
    local specID = CurrentSpecID()
    local activeSpec = specID and db.specAuthorSelection[tostring(specID)] or nil
    for _, slot in ipairs(SLOT_ORDER) do
        local category = SlotCategory(slot)
        local authorID = type(activeSpec) == "table" and activeSpec[slot] or nil
        if not AuthorExists(category, authorID) then authorID = db.authorSelection[slot] end
        if not AuthorExists(category, authorID) then authorID = SLOTS[slot].author end
        db.authorSelection[slot] = authorID
    end
end

local function EnsureDB()
    EXBossDataDB = EXBossDataDB or {}
    if not IsBossDB(EXBossDataDB.bossConfig) then EXBossDataDB.bossConfig = NewBossDB() end
    local db = EXBossDataDB.bossConfig
    local oldSchema = tonumber(db.schema) or 0
    if type(db.specAuthorSelection) ~= "table" then db.specAuthorSelection = {} end
    MigrateToAuthorBoundUsers(db, oldSchema)
    MigrateToAccountWideAuthorSelection(db, oldSchema)
    db.schema = SCHEMA
    for _, slot in ipairs(SLOT_ORDER) do
        local category = SlotCategory(slot)
        local current = db.selection[slot]
        if not IsValidUser(category, current) then db.selection[slot] = EnsureLegacyUser(slot) end
        local authorID = db.authorSelection[slot]
        if not AuthorExists(category, authorID) then
            authorID = SLOTS[slot].author
            db.authorSelection[slot] = authorID
        end
        EnsureBoundUser(db, category, authorID)
    end
    db.activeSlot = NormalizeSlot(db.activeSlot) or "mplus_dps"
    return db
end

local function AuthorForSlot(slot)
    slot = NormalizeSlot(slot)
    if not slot then return nil end
    local db, category = EnsureDB(), SlotCategory(slot)
    local selected = db.authorSelection[slot]
    if AuthorExists(category, selected) then return selected end
    return SLOTS[slot].author
end

local function Selected(slot)
    slot = NormalizeSlot(slot)
    if not slot then return nil end
    local db, category = EnsureDB(), SlotCategory(slot)
    return EnsureBoundUser(db, category, AuthorForSlot(slot))
end

local function Activate(slot)
    slot = NormalizeSlot(slot)
    local api = API()
    local userID, authorID = Selected(slot), AuthorForSlot(slot)
    if not api or not slot or not userID or not authorID then return false, "active configuration unavailable" end
    return api.ActivateUserConfiguration(SlotCategory(slot), userID, authorID)
end

local function NotifyRuntime()
    local aura = ExBoss.AuraSound
    if aura and type(aura.RefreshActiveRegistrations) == "function" then aura:RefreshActiveRegistrations() end
end

local function RefreshAuraSound()
    local aura = ExBoss.AuraSound
    if aura and type(aura.RefreshActiveRegistrations) == "function" then aura:RefreshActiveRegistrations() end
end

function BossConfig:Ensure()
    return EnsureDB()
end

function BossConfig:GetSlotKeys(scene)
    local category, out = scene and tostring(scene):lower() or nil, {}
    for _, slot in ipairs(SLOT_ORDER) do
        if not category or SlotCategory(slot) == category then out[#out + 1] = slot end
    end
    return out
end

function BossConfig:GetSlotLabel(slot)
    local meta = SLOTS[NormalizeSlot(slot) or ""]
    return meta and meta.label or tostring(slot or "")
end

function BossConfig:GetSlotItems(scene)
    local out = {}
    for _, slot in ipairs(self:GetSlotKeys(scene)) do out[#out + 1] = { self:GetSlotLabel(slot), slot } end
    return out
end

function BossConfig:GetRuntimeSlotForScene(scene)
    local category = tostring(scene or ""):lower()
    return (category == "mplus" or category == "raid") and category .. "_" .. CurrentRole() or nil
end

function BossConfig:ActivateSlot(slot)
    return Activate(slot)
end

function BossConfig:ActivateScene(scene)
    return Activate(self:GetRuntimeSlotForScene(scene))
end

-- Settings pages may build their own scene Runtime for display.  This does
-- not notify combat modules and never replaces the other scene Runtime.
function BossConfig:EnsureSceneRuntime(scene)
    return Activate(self:GetRuntimeSlotForScene(scene))
end

function BossConfig:GetSelectedAuthor(slot)
    return AuthorForSlot(slot)
end

function BossConfig:GetBaseSelectedAuthor(slot)
    slot = NormalizeSlot(slot)
    if not slot then return nil end
    local db, category = EnsureDB(), SlotCategory(slot)
    local selected = db.authorSelection[slot]
    return AuthorExists(category, selected) and selected or SLOTS[slot].author
end

function BossConfig:GetSelectedUser(slot)
    return Selected(slot)
end

-- Compatibility name retained for callers written during the transitional
-- Author-preset UI.  It now has the same, correct Author meaning.
function BossConfig:GetSelectedAuthorPreset(slot)
    return AuthorForSlot(slot)
end

function BossConfig:GetAuthorPresetItems(slot)
    slot = NormalizeSlot(slot)
    if not slot then return {} end
    local api = API()
    local out = {}
    for _, row in ipairs(api and api.ListAuthors and api.ListAuthors(SlotCategory(slot)) or {}) do
        local name = Trim(row.name) or row.id
        local author = Trim(row.author)
        if author then name = name .. " · " .. author end
        out[#out + 1] = { name, row.id }
    end
    table.sort(out, function(left, right) return tostring(left[1]) < tostring(right[1]) end)
    return out
end

function BossConfig:SetSelectedAuthorPreset(slot, authorID)
    slot, authorID = NormalizeSlot(slot), Trim(authorID)
    if not slot or not AuthorExists(SlotCategory(slot), authorID) then return false, "author artifact not found" end
    local db = EnsureDB()
    db.authorSelection[slot] = authorID
    local userID, reason = EnsureBoundUser(db, SlotCategory(slot), authorID)
    if not userID then return false, reason end
    return true
end

function BossConfig:GetAuthorItems(slot)
    return self:GetAuthorPresetItems(slot)
end

function BossConfig:SetSelectedAuthor(slot, authorID)
    return self:SetSelectedAuthorPreset(slot, authorID)
end

local function CurrentRuntime(category, slot)
    local api = API()
    slot = NormalizeSlot(slot) or BossConfig:GetRuntimeSlotForScene(category)
    local context = api and api.GetCurrentConfiguration(category)
    if not context or context.category ~= category or context.userID ~= Selected(slot)
        or context.authorID ~= AuthorForSlot(slot) then return nil end
    return api.GetRuntime(category)
end

function BossConfig:GetRuntimeConfig(scene, slot)
    return CurrentRuntime(tostring(scene):lower(), slot)
end
function BossConfig:GetRuntimeEvent(scene, eventID)
    local runtime = API() and API().GetRuntime(scene)
    local eid = tonumber(eventID)
    return type(runtime) == "table" and type(runtime.events) == "table" and eid
        and (runtime.events[eid] or runtime.events[tostring(eid)]) or nil
end

-- ENCOUNTER_WARNING 的机制参数由 EXBossData 静态规则定义；显示方式完整沿用
-- Boss 页面原有「被点名提示」配置，不新增或替换任何 GUI 字段。
function BossConfig:GetEncounterWarningAlertConfig(scene, eventID)
    local row = self:GetRuntimeEvent(tostring(scene or ""):lower(), eventID)
    if type(row) ~= "table" or row.targetAlertStartEnabled ~= true then
        return nil
    end
    return row
end

function BossConfig:IsEncounterWarningAlertEnabled(scene, eventID)
    return self:GetEncounterWarningAlertConfig(scene, eventID) ~= nil
end

-- Boss 页面上的倒数文字和计时条改名都是事件行自身的纯文本字段。这里不能再
-- 从语音 trigger 推导任何后备文字，否则会把两套独立配置重新耦合起来。
local function NormalizeLinkedText(value)
    if type(value) ~= "string" then return "" end
    return value:gsub("^%s+", ""):gsub("%s+$", "")
end

function BossConfig:ResolveLinkedTextFields(row)
    row = type(row) == "table" and row or {}
    return {
        preAlertText = NormalizeLinkedText(row.preAlertText),
        timerBarRenameText = NormalizeLinkedText(row.timerBarRenameText),
    }
end

function BossConfig:GetRuntimeDungeonOption(key, option)
    local runtime = API() and API().GetRuntime("mplus")
    local row = type(runtime) == "table" and type(runtime.dungeonOptions) == "table" and runtime.dungeonOptions[key] or nil
    return type(row) == "table" and row[tostring(option or "")] or nil
end

function BossConfig:GetRuntimeEncounterOption(id, option)
    local runtime = API() and API().GetRuntime("raid")
    local row = type(runtime) == "table" and type(runtime.encounterOptions) == "table" and runtime.encounterOptions[tonumber(id)] or nil
    return type(row) == "table" and row[tostring(option or "")] or nil
end

function BossConfig:GetMplusDungeonAuraSoundView(dungeonKey, slot)
    return API().GetMplusDungeonAuraSoundView(Selected(NormalizeSlot(slot) or self:GetRuntimeSlotForScene("mplus")), dungeonKey)
end
function BossConfig:GetMplusDungeonAuraSoundActionView(dungeonKey, actionID, slot)
    return API().GetMplusDungeonAuraSoundActionView(Selected(NormalizeSlot(slot) or self:GetRuntimeSlotForScene("mplus")), dungeonKey, actionID)
end
function BossConfig:SetMplusDungeonAuraSoundActionFields(slot, dungeonKey, actionID, fields)
    local api = API()
    local userID = Selected(NormalizeSlot(slot) or self:GetRuntimeSlotForScene("mplus"))
    local ok, reason = api.SetMplusDungeonAuraSoundActionFields(userID, dungeonKey, actionID, fields)
    if ok then RefreshAuraSound() end
    return ok, reason
end
function BossConfig:CreateMplusDungeonAuraSoundAction(slot, dungeonKey, actionID, action)
    local api = API()
    local userID = Selected(NormalizeSlot(slot) or self:GetRuntimeSlotForScene("mplus"))
    local ok, reason = api.CreateMplusDungeonAuraSoundAction(userID, dungeonKey, actionID, action)
    if ok then RefreshAuraSound() end
    return ok, reason
end

function BossConfig:IsSceneEnabled(scene)
    local category = tostring(scene or ""):lower()
    EXBOSS12S2 = EXBOSS12S2 or {}; EXBOSS12S2.ui = EXBOSS12S2.ui or {}; EXBOSS12S2.ui.general = EXBOSS12S2.ui.general or {}
    local general = EXBOSS12S2.ui.general
    if general.disableEXBossInRaid == nil then
        general.disableEXBossInRaid = (general.bossAlertsEnabledRaid ~= true)
    else
        general.disableEXBossInRaid = (general.disableEXBossInRaid == true)
    end
    return category == "mplus" and EXBOSS12S2.ui.general.bossAlertsEnabledMplus ~= false
        or category == "raid" and general.disableEXBossInRaid ~= true
end
function BossConfig:IsCurrentSceneEnabled()
    local _, instanceType = GetInstanceInfo()
    if instanceType == "party" then return self:IsSceneEnabled("mplus"), "mplus" end
    if instanceType == "raid" then return self:IsSceneEnabled("raid"), "raid" end
    return false, nil
end

function BossConfig:GetAuthorConfigurationItems(category)
    category = tostring(category or "")
    if category ~= "mplus" and category ~= "raid" then return {} end
    local api, out = API(), {}
    for _, row in ipairs(api and api.ListAuthors and api.ListAuthors(category) or {}) do
        local id = Trim(row.id)
        if id then
            out[#out + 1] = {
                category = category,
                id = id,
                name = Trim(row.name) or id,
                author = Trim(row.author) or "",
                imported = row.imported == true,
            }
        end
    end
    table.sort(out, function(left, right)
        if left.imported ~= right.imported then return left.imported == true end
        return tostring(left.name) < tostring(right.name)
    end)
    return out
end

-- Transitional callers used this name for a list of User configurations.
-- Returning Authors here prevents that old UI surface from exposing Users again.
function BossConfig:GetConfigurationItems(category)
    return self:GetAuthorConfigurationItems(category)
end

function BossConfig:RenameAuthorConfiguration(category, authorID, name)
    category, authorID, name = tostring(category or ""), Trim(authorID), Trim(name)
    local api = API()
    if (category ~= "mplus" and category ~= "raid") or not authorID or not name
        or not api or type(api.RenameImportedAuthor) ~= "function" then
        return false, "only imported Author configurations can be renamed"
    end
    return api.RenameImportedAuthor(category, authorID, name)
end

function BossConfig:IsAuthorConfigurationNameAvailable(category, name)
    category, name = tostring(category or ""), Trim(name)
    local api = API()
    return (category == "mplus" or category == "raid") and name ~= nil
        and api and type(api.IsAuthorNameAvailable) == "function"
        and api.IsAuthorNameAvailable(category, name) == true
end

function BossConfig:DeleteAuthorConfiguration(category, authorID)
    category, authorID = tostring(category or ""), Trim(authorID)
    local api = API()
    if (category ~= "mplus" and category ~= "raid") or not authorID
        or not api or type(api.DeleteImportedAuthor) ~= "function" then
        return false, "only imported Author configurations can be deleted"
    end

    local isImported = false
    for _, row in ipairs(api.ListAuthors and api.ListAuthors(category) or {}) do
        if row.id == authorID then isImported = row.imported == true; break end
    end
    if not isImported then return false, "only imported Author configurations can be deleted" end

    local db = EnsureDB()
    for _, slot in ipairs(self:GetSlotKeys(category)) do
        if db.authorSelection[slot] == authorID then db.authorSelection[slot] = SLOTS[slot].author end
    end
    for _, selections in pairs(db.specAuthorSelection) do
        if type(selections) == "table" then
            for _, slot in ipairs(self:GetSlotKeys(category)) do
                if selections[slot] == authorID then selections[slot] = SLOTS[slot].author end
            end
        end
    end
    if type(db.userByAuthor[category]) == "table" then
        -- The User value table remains in EXBossDataDB.users so deleting an
        -- imported Author can never destroy the player's personal data.
        db.userByAuthor[category][authorID] = nil
    end
    local ok, reason = api.DeleteImportedAuthor(category, authorID)
    if not ok then return false, reason end
    self:PublishRuntimeSelection()
    return true
end

function BossConfig:ExportAuthorUserPair(category, authorID)
    category, authorID = tostring(category or ""), Trim(authorID)
    if (category ~= "mplus" and category ~= "raid") or not AuthorExists(category, authorID) then
        return nil, "Author configuration not found"
    end
    local api, db = API(), EnsureDB()
    if not api or type(api.ExportAuthorConfiguration) ~= "function" or type(api.ExportUserConfiguration) ~= "function" then
        return nil, "configuration export unavailable"
    end
    local userID, userReason = EnsureBoundUser(db, category, authorID)
    if not userID then return nil, userReason end
    local author, authorReason = api.ExportAuthorConfiguration(category, authorID)
    if type(author) ~= "table" then return nil, authorReason or "Author configuration not found" end
    local values, valueReason = api.ExportUserConfiguration(category, userID)
    if type(values) ~= "table" then return nil, valueReason or "User configuration not found" end
    return { author = author, user = { values = values } }
end

-- Create a fully independent editable Author from the selected Author.  The
-- source may be built in or imported, but it is never changed: its Author
-- values and its bound User override are exported as copies before the new
-- pair is imported under the caller-provided name.
function BossConfig:DuplicateAuthorConfiguration(category, authorID, name)
    category, authorID, name = tostring(category or ""), Trim(authorID), Trim(name)
    if (category ~= "mplus" and category ~= "raid") or not authorID or not name
        or not AuthorExists(category, authorID) then
        return false, "Author configuration not found"
    end

    local api = API()
    if not api or type(api.ExportAuthorConfiguration) ~= "function"
        or type(api.ImportAuthorConfiguration) ~= "function"
        or type(api.ImportUserConfiguration) ~= "function"
        or type(api.IsAuthorNameAvailable) ~= "function" then
        return false, "configuration copy unavailable"
    end
    if api.IsAuthorNameAvailable(category, name) ~= true then
        return false, "Author configuration name already exists"
    end

    local author, authorReason = api.ExportAuthorConfiguration(category, authorID)
    if type(author) ~= "table" then
        return false, authorReason or "Author configuration not found"
    end

    -- A missing binding means this Author has no player overrides yet.  Copy
    -- that state as an empty independent override rather than creating or
    -- modifying a binding on the source configuration.
    local values = {}
    local db = EnsureDB()
    local bindings = type(db.userByAuthor) == "table" and db.userByAuthor[category] or nil
    local userID = type(bindings) == "table" and bindings[authorID] or nil
    if IsValidUser(category, userID) then
        if type(api.ExportUserConfiguration) ~= "function" then
            return false, "configuration copy unavailable"
        end
        local userReason
        values, userReason = api.ExportUserConfiguration(category, userID)
        if type(values) ~= "table" then
            return false, userReason or "user configuration not found"
        end
    end

    return self:ImportAuthorUserPair(category, {
        author = author,
        user = { values = values },
    }, name)
end

function BossConfig:BuildSceneTransfer(category)
    category = tostring(category or "")
    if category ~= "mplus" and category ~= "raid" then return nil, "invalid configuration category" end
    local result, pairIDs = { category = category, pairs = {}, assignments = {} }, {}
    for _, slot in ipairs(self:GetSlotKeys(category)) do
        local authorID = AuthorForSlot(slot)
        local pairID = pairIDs[authorID]
        if not pairID then
            local pair, reason = self:ExportAuthorUserPair(category, authorID)
            if not pair then return nil, reason end
            pairID = "pair" .. tostring(#result.pairs + 1)
            pair.id = pairID
            result.pairs[#result.pairs + 1] = pair
            pairIDs[authorID] = pairID
        end
        result.assignments[slot] = pairID
    end
    return result
end

function BossConfig:ImportAuthorUserPair(category, pair, importedName)
    category = tostring(category or "")
    if (category ~= "mplus" and category ~= "raid") or type(pair) ~= "table"
        or type(pair.author) ~= "table" or type(pair.user) ~= "table"
        or type(pair.author.values) ~= "table" or type(pair.user.values) ~= "table" then
        return false, "invalid Author + User configuration"
    end
    local api = API()
    if not api or type(api.ImportAuthorConfiguration) ~= "function" or type(api.ImportUserConfiguration) ~= "function" then
        return false, "configuration import unavailable"
    end
    -- Keep the source payload immutable.  The receiver chooses the visible
    -- name of every imported Author, while id generation remains internal.
    local artifact = pair.author
    local displayName = Trim(importedName)
    if displayName then
        artifact = {
            id = pair.author.id,
            name = displayName,
            author = pair.author.author,
            values = pair.author.values,
        }
    end
    local ok, authorID = api.ImportAuthorConfiguration(category, artifact)
    if not ok then return false, authorID end
    local userOK, userID = api.ImportUserConfiguration(category, pair.user.values)
    if not userOK then
        if type(api.DeleteImportedAuthor) == "function" then api.DeleteImportedAuthor(category, authorID) end
        return false, userID
    end
    local db = EnsureDB()
    db.userByAuthor[category][authorID] = userID
    return true, { authorID = authorID, userID = userID }
end

local function PairMap(pairs)
    local out = {}
    for _, pair in ipairs(type(pairs) == "table" and pairs or {}) do
        local id = type(pair) == "table" and Trim(pair.id) or nil
        if not id or out[id] then return nil, "invalid or duplicate configuration pair" end
        out[id] = pair
    end
    return out
end

-- This enforces the import order visible in the UI: role checkboxes first
-- determine the unique pairs, then only those pairs are imported, then only
-- the checked roles are switched to the newly imported Authors.
function BossConfig:ImportSelectedScene(category, pairs, assignments, selectedSlots, namesByPairID)
    category = tostring(category or "")
    if category ~= "mplus" and category ~= "raid" then return false, "invalid configuration category" end
    local byID, mapReason = PairMap(pairs)
    if not byID then return false, mapReason end
    assignments = type(assignments) == "table" and assignments or {}
    selectedSlots = type(selectedSlots) == "table" and selectedSlots or {}

    local required, ordered = {}, {}
    for _, slot in ipairs(self:GetSlotKeys(category)) do
        if selectedSlots[slot] == true then
            local pairID = Trim(assignments[slot])
            if not pairID or not byID[pairID] then return false, "selected role has no valid configuration pair" end
            if not required[pairID] then required[pairID] = true; ordered[#ordered + 1] = pairID end
        end
    end
    if #ordered == 0 then return true, { imported = 0, assignments = 0 } end
    local imported = {}
    namesByPairID = type(namesByPairID) == "table" and namesByPairID or {}
    for _, pairID in ipairs(ordered) do
        local pair = byID[pairID]
        local displayName = Trim(namesByPairID[pairID])
        local ok, result = self:ImportAuthorUserPair(category, pair, displayName)
        if not ok then return false, result end
        imported[pairID] = result.authorID
    end

    local db = EnsureDB()
    local target = db.authorSelection
    local assignmentCount = 0
    for _, slot in ipairs(self:GetSlotKeys(category)) do
        if selectedSlots[slot] == true then
            target[slot] = imported[Trim(assignments[slot])]
            assignmentCount = assignmentCount + 1
        end
    end
    return true, { imported = #ordered, assignments = assignmentCount }
end

function BossConfig:PublishRuntimeSelection()
    local _, instanceType = GetInstanceInfo()
    local scene = instanceType == "party" and "mplus" or instanceType == "raid" and "raid" or nil
    -- Outside an instance, M+ is the only eager scene.  Visiting the raid
    -- settings page must never make Raid Runtime a future login default.
    local slot = scene and self:GetRuntimeSlotForScene(scene) or self:GetRuntimeSlotForScene("mplus")
    local ok, reason = Activate(slot)
    if ok then NotifyRuntime() end
    if ExwindTools and type(ExwindTools.UpdateState) == "function" then
        ExwindTools:UpdateState("ExBoss.BossConfig.SelectionChanged", {})
    end
    return ok, reason
end

function BossConfig:ApplyPersistedChange()
    return true
end

if ExwindTools and ExwindTools.WatchState then
    ExwindTools:WatchState("RoleKey", "ExBoss.BossConfig.Role", function() BossConfig:PublishRuntimeSelection() end)
    ExwindTools:WatchState("SpecID", "ExBoss.BossConfig.Spec", function() BossConfig:PublishRuntimeSelection() end)
end
if ExwindTools and ExwindTools.RegisterEvent then
    ExwindTools:RegisterEvent("ADDON_LOADED", "ExBoss.BossConfig.Init", function(_, addonName)
        if tostring(addonName or ""):lower() == "exboss" then BossConfig:Ensure(); BossConfig:PublishRuntimeSelection() end
    end)
    ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", "ExBoss.BossConfig.Enter", function() BossConfig:PublishRuntimeSelection() end)
end
