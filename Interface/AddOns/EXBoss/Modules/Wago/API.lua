---@diagnostic disable: undefined-global
-- TEST
-- Wago profiles expose complete Author + bound-User pairs. User overrides are
-- intentionally never listed or selected on their own. ImportProfile also
-- accepts the current EXBXC v7 bundle format from EXBoss's Import/Export page.

EXBossWagoAPI = EXBossWagoAPI or {}
local PREFIX = "[EXBoss Author] "

local function IE() return ExBoss and ExBoss.Voice and ExBoss.Voice.ImportExport end

local function Trim(value)
    local text = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
    return text ~= "" and text or nil
end

-- The in-game form asks the user for every imported name. A third-party
-- button has no such form, so create a stable, readable non-conflicting name
-- instead of silently failing when the receiving character has a default or
-- previously imported configuration with the same display name.
local function UniqueImportedName(preferred, isAvailable, reserved)
    local base = Trim(preferred) or "Imported Configuration"
    reserved = reserved or {}
    local candidate, index = base, 0
    while reserved[candidate] == true or isAvailable(candidate) ~= true do
        index = index + 1
        if index > 10000 then return nil, "could not allocate imported configuration name" end
        candidate = base .. (index == 1 and " (Imported)" or " (Imported " .. tostring(index) .. ")")
    end
    reserved[candidate] = true
    return candidate
end

local function SelectAllAssignedSlots(scene)
    local selected = {}
    for slot in pairs(type(scene) == "table" and scene.assignments or {}) do
        selected[slot] = true
    end
    return selected
end

local function PairPreferredName(bundleName, scene, pair)
    local packageName = Trim(bundleName)
    if packageName then
        if type(scene) == "table" and #(scene.pairs or {}) > 1 then
            return packageName ..
            " - " .. (Trim(pair and pair.author and pair.author.name) or Trim(pair and pair.id) or "Configuration")
        end
        return packageName
    end
    return Trim(pair and pair.author and pair.author.name) or Trim(pair and pair.id) or "Imported Configuration"
end

local function AppearancePreferredName(bundle)
    local appearanceName = Trim(type(bundle) == "table" and bundle.appearance and bundle.appearance.name)
        or "Imported Appearance"
    local packageName = Trim(type(bundle) == "table" and bundle.name)
    return packageName and packageName .. " - " .. appearanceName or appearanceName
end

local function BuildPairImportNames(bossCfg, category, scene, bundleName)
    local names, reserved = {}, {}
    for _, pair in ipairs(type(scene) == "table" and scene.pairs or {}) do
        local name, reason = UniqueImportedName(PairPreferredName(bundleName, scene, pair), function(candidate)
            return bossCfg:IsAuthorConfigurationNameAvailable(category, candidate) == true
        end, reserved)
        if not name then return nil, reason end
        names[pair.id] = name
    end
    return names
end

local function ImportBundleAndActivate(bundle)
    local profiles = ExBoss and ExBoss.AppearanceProfiles
    local bossCfg = ExBoss and ExBoss.BossConfig
    local result = { appearance = false, mplus = nil, raid = nil, names = {} }
    local switched = false

    if bundle.appearance ~= nil then
        if type(profiles) ~= "table" or type(profiles.ImportProfilePayload) ~= "function"
            or type(profiles.ActivateProfile) ~= "function" or type(profiles.IsProfileNameAvailable) ~= "function" then
            return false, "appearance profile import unavailable"
        end
        local appearanceName, nameReason = UniqueImportedName(AppearancePreferredName(bundle), function(candidate)
            return profiles:IsProfileNameAvailable(candidate) == true
        end)
        if not appearanceName then return false, nameReason end
        local ok, profileID = profiles:ImportProfilePayload({
            name = appearanceName,
            appearance = bundle.appearance.appearance,
        })
        if not ok then return false, profileID end
        local activated, reason = profiles:ActivateProfile(profileID)
        if not activated then return false, reason end
        result.appearance, result.names.appearance, switched = true, appearanceName, true
    end

    for _, category in ipairs({ "mplus", "raid" }) do
        local scene = type(bundle.scenes) == "table" and bundle.scenes[category] or nil
        if scene ~= nil then
            if type(bossCfg) ~= "table" or type(bossCfg.ImportSelectedScene) ~= "function" then
                return false, "Boss configuration import unavailable"
            end
            local selectedSlots = SelectAllAssignedSlots(scene)
            local namesByPairID, nameReason = BuildPairImportNames(bossCfg, category, scene, bundle.name)
            if not namesByPairID then return false, nameReason end
            local ok, importResult = bossCfg:ImportSelectedScene(
                category, scene.pairs, scene.assignments, selectedSlots, namesByPairID
            )
            if not ok then return false, importResult end
            result[category] = importResult
            result.names[category] = namesByPairID
            switched = switched or (tonumber(importResult.assignments) or 0) > 0
        end
    end

    if switched and type(bossCfg) == "table" and type(bossCfg.PublishRuntimeSelection) == "function" then
        local ok, reason = bossCfg:PublishRuntimeSelection()
        if not ok then return false, reason end
    end
    return true, result, switched
end

local function ImportLegacyAndName(ie, profile)
    local bossCfg = ExBoss and ExBoss.BossConfig
    if type(bossCfg) ~= "table" or type(bossCfg.IsAuthorConfigurationNameAvailable) ~= "function" then
        return false, "Boss configuration import unavailable"
    end
    local importedName, reason = UniqueImportedName(profile.author and profile.author.name, function(candidate)
        return bossCfg:IsAuthorConfigurationNameAvailable(profile.category, candidate) == true
    end)
    if not importedName then return false, reason end
    local ok, result = ie:ImportUserConfigurationPayload({
        version = 6,
        payloadType = "exboss_author_user_values",
        profile = profile,
    }, importedName)
    if not ok then return false, result end
    if type(result) == "table" then
        result.importName = importedName
        result.reloadRequired = false
    end
    return true, result
end

local function Refs()
    local bossCfg, refs, used = ExBoss and ExBoss.BossConfig, {}, {}
    if type(bossCfg) ~= "table" or type(bossCfg.GetAuthorConfigurationItems) ~= "function" then return refs end
    for _, category in ipairs({ "mplus", "raid" }) do
        for _, row in ipairs(bossCfg:GetAuthorConfigurationItems(category) or {}) do
            local id = tostring(row.id or "")
            if id ~= "" then
                local key = PREFIX .. category .. ":" .. id
                if not used[key] then refs[key], used[key] = { category = category, authorID = id }, true end
            end
        end
    end
    return refs
end

function EXBossWagoAPI:ExportProfile(key)
    local ref, ie = type(key) == "string" and Refs()[key] or nil, IE()
    local bossCfg = ExBoss and ExBoss.BossConfig
    if not (ref and ie and bossCfg and bossCfg.ExportAuthorUserPair and ie.ExportAuthorUserPairString) then return nil end
    local pair = bossCfg:ExportAuthorUserPair(ref.category, ref.authorID)
    return pair and ie:ExportAuthorUserPairString(ref.category, pair) or nil
end

function EXBossWagoAPI:ImportProfile(text)
    local ie = IE()
    if not ie then return false, "user configuration import unavailable" end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        return false, "cannot import configuration in combat"
    end

    -- DecodeTransfer accepts both legacy v6 Author + User payloads and v7
    -- bundles emitted by EXBoss's own Import/Export page.
    local transfer, reason = ie:DecodeTransfer(text)
    if not transfer then return false, reason end
    if transfer.kind == "legacyBoss" then
        return ImportLegacyAndName(ie, transfer.profile)
    end
    if transfer.kind ~= "bundle" or type(transfer.bundle) ~= "table" then
        return false, "unsupported configuration payload"
    end

    local ok, result, switched = ImportBundleAndActivate(transfer.bundle)
    if not ok then return false, result end
    -- A v7 bundle restores its appearance and role assignments by default.
    -- Wago Creator owns the single reload after its whole import batch; this
    -- API must not interrupt that batch with its own ReloadUI call.
    -- Direct consumers can use this flag to reload after their own batch.
    result.reloadRequired = switched == true
    return true, result
end

function EXBossWagoAPI:DecodeProfileString(text)
    local ie = IE()
    return ie and ie:DecodeUserConfigurationPayload(text) or nil
end

function EXBossWagoAPI:GetProfileKeys()
    local keys = {}
    for key in pairs(Refs()) do keys[key] = true end
    return keys
end

function EXBossWagoAPI:GetCurrentProfileKey() return nil end

function EXBossWagoAPI:GetProfileAssignments() return nil end

function EXBossWagoAPI:SetProfile() return false end

function EXBossWagoAPI:OpenConfig()
    local router = _G.ExwindTools and _G.ExwindTools.PanelRouter
    if router and router.Open then router:Open("importexport") end
end

function EXBossWagoAPI:CloseConfig()
    local router = _G.ExwindTools and _G.ExwindTools.PanelRouter
    if router and router.Close then router:Close("importexport") end
end
