---@diagnostic disable: undefined-global

-- Appearance profiles own exactly the non-Boss/non-trash settings declared by
-- the settings-page router.  Boss data, Author/User layers and trash data
-- must never cross this boundary.

local ExwindTools = _G.ExwindTools
if not ExwindTools then
    return
end

ExBoss = ExBoss or {}
ExBoss.AppearanceProfiles = ExBoss.AppearanceProfiles or {}
local Profiles = ExBoss.AppearanceProfiles
local L = ExBoss.L or setmetatable({}, { __index = function(_, key) return key end })

local PROFILE_SCHEMA = 1
local TRANSFER_VERSION = 1
local TRANSFER_PREFIX = "!EXBOSSAP1!"
local MAX_TRANSFER_LENGTH = 250000
local MAX_VALUE_DEPTH = 40
local MAX_VALUE_COUNT = 30000
-- ui.general owns the CVar-backed global switches.  It must remain in every
-- appearance payload even if a runtime settings-route registration is late or
-- absent when the profile is exported.
local REQUIRED_ROOT_PATHS = { "ui.general" }

local function AppearanceSpec()
    local page = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.GlobalSettingsPage
    if type(page) ~= "table" or type(page.GetAppearanceProfileSpec) ~= "function" then
        return nil, "appearance settings route is unavailable"
    end
    local raw = page:GetAppearanceProfileSpec()
    if type(raw) ~= "table" or type(raw.modules) ~= "table" or type(raw.roots) ~= "table" then
        return nil, "appearance settings route returned an invalid specification"
    end
    local spec = { moduleKeys = {}, moduleKeySet = {}, rootPaths = {}, rootPathSet = {} }
    for _, key in ipairs(raw.modules) do
        if type(key) == "string" and key ~= "" and not spec.moduleKeySet[key] then
            spec.moduleKeySet[key] = true
            spec.moduleKeys[#spec.moduleKeys + 1] = key
        end
    end
    for _, path in ipairs(raw.roots) do
        if type(path) == "string" and path:match("^[%a_][%w_]*(%.[%a_][%w_]*)*$") and not spec.rootPathSet[path] then
            spec.rootPathSet[path] = true
            spec.rootPaths[#spec.rootPaths + 1] = path
        end
    end
    for _, path in ipairs(REQUIRED_ROOT_PATHS) do
        if not spec.rootPathSet[path] then
            spec.rootPathSet[path] = true
            spec.rootPaths[#spec.rootPaths + 1] = path
        end
    end
    return spec
end

local function Trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function Root()
    local root = _G.EXBOSS12S2
    if type(root) ~= "table" then
        return nil, "EXBoss settings storage is unavailable"
    end
    if type(root.ModuleDB) ~= "table" then
        root.ModuleDB = {}
    end
    return root
end

-- Keep the CVar-backed general switches on the same round trip that the
-- pre-refactor exporter used: capture reads their live CVar state into the
-- exported copy, and apply writes an imported value back immediately.
-- This is intentionally local to the transferable ui.general root; it never
-- reads or writes Boss/trash settings.
local function ReadCVarValue(name)
    local key = tostring(name or "")
    if key == "" then return nil end
    local ok, value
    if C_CVar and C_CVar.GetCVar then
        ok, value = pcall(C_CVar.GetCVar, key)
    end
    if (not ok or value == nil) and type(GetCVar) == "function" then
        ok, value = pcall(GetCVar, key)
    end
    if not ok or value == nil then return nil end
    local text = tostring(value)
    return text ~= "" and text or nil
end

local function WriteCVarValue(name, value)
    local key, text = tostring(name or ""), tostring(value or "")
    if key == "" or text == "" then return false end
    local ok = false
    if C_CVar and C_CVar.SetCVar then
        ok = pcall(C_CVar.SetCVar, key, text)
        if ok then return true end
    end
    if type(SetCVar) == "function" then
        ok = pcall(SetCVar, key, text)
        if ok then return true end
    end
    return false
end

local function SyncGeneralCVarsIntoExport(general)
    if type(general) ~= "table" then return general end
    local warnings = ReadCVarValue("encounterWarningsEnabled")
    if warnings ~= nil then
        general.encounterWarningsEnabled = warnings ~= "0"
    end
    local timeline = ReadCVarValue("encounterTimelineEnabled")
    if timeline ~= nil then
        general.disableBlizzardEncounterTimeline = timeline == "0"
    end
    return general
end

local function ApplyGeneralCVarsFromImport(general)
    if type(general) ~= "table" then return end
    if general.encounterWarningsEnabled ~= nil then
        WriteCVarValue("encounterWarningsEnabled", general.encounterWarningsEnabled ~= false and "1" or "0")
    end
    if general.disableBlizzardEncounterTimeline ~= nil then
        WriteCVarValue("encounterTimelineEnabled", general.disableBlizzardEncounterTimeline == true and "0" or "1")
    end
end

local function IsFiniteNumber(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function Copy(value, seen)
    local kind = type(value)
    if kind == "nil" or kind == "boolean" or kind == "string" then
        return value
    end
    if kind == "number" then
        if not IsFiniteNumber(value) then
            return nil, "unsupported numeric value"
        end
        return value
    end
    if kind ~= "table" then
        return nil, "unsupported value type: " .. kind
    end

    seen = seen or {}
    if seen[value] then
        return nil, "cyclic configuration table"
    end
    seen[value] = true

    local out = {}
    for key, child in pairs(value) do
        local keyKind = type(key)
        if keyKind ~= "string" and keyKind ~= "number" then
            seen[value] = nil
            return nil, "unsupported configuration key"
        end
        if keyKind == "number" and not IsFiniteNumber(key) then
            seen[value] = nil
            return nil, "unsupported numeric key"
        end
        local copied, reason = Copy(child, seen)
        if reason then
            seen[value] = nil
            return nil, reason
        end
        out[key] = copied
    end

    seen[value] = nil
    return out
end

local function ValidateValue(value, state, depth)
    local kind = type(value)
    if kind == "nil" or kind == "boolean" or kind == "string" then
        return true
    end
    if kind == "number" then
        return IsFiniteNumber(value), "unsupported numeric value"
    end
    if kind ~= "table" then
        return false, "unsupported value type: " .. kind
    end
    if depth >= MAX_VALUE_DEPTH then
        return false, "configuration nesting is too deep"
    end
    if state.seen[value] then
        return false, "cyclic configuration table"
    end
    state.count = state.count + 1
    if state.count > MAX_VALUE_COUNT then
        return false, "configuration contains too many values"
    end

    state.seen[value] = true
    for key, child in pairs(value) do
        local keyKind = type(key)
        if keyKind ~= "string" and keyKind ~= "number" then
            state.seen[value] = nil
            return false, "unsupported configuration key"
        end
        if keyKind == "number" and not IsFiniteNumber(key) then
            state.seen[value] = nil
            return false, "unsupported numeric key"
        end
        local ok, reason = ValidateValue(child, state, depth + 1)
        if not ok then
            state.seen[value] = nil
            return false, reason
        end
    end
    state.seen[value] = nil
    return true
end

local function Only(tableValue, allowed)
    if type(tableValue) ~= "table" then
        return false
    end
    for key in pairs(tableValue) do
        if allowed[key] ~= true then
            return false
        end
    end
    return true
end

-- ModuleDB can contain transient runtime fields (for example FlashText's
-- temporary duration override).  The declared module schema is the only
-- trustworthy boundary for a transferable module configuration.
local function ProjectDeclaredModule(moduleKey)
    local declarations = ExwindTools.ModuleDefaultDeclarations
    local registered = type(declarations) == "table" and declarations[moduleKey] or nil
    if type(registered) ~= "table" or type(registered.schema) ~= "table"
        or type(ExwindTools.ExportModuleDefaults) ~= "function" then
        return nil, "module has no declared export schema"
    end

    local ok, projected = pcall(ExwindTools.ExportModuleDefaults, ExwindTools, moduleKey)
    if not ok or type(projected) ~= "table" then
        return nil, tostring(projected or "module projection failed")
    end

    local out = {}
    for _, rule in ipairs(registered.schema) do
        local group = projected[rule.group]
        if type(group) ~= "table" then
            return nil, "module projection is missing group: " .. tostring(rule.group)
        end
        if rule.root == true then
            for field, value in pairs(group) do
                out[field] = value
            end
        else
            out[rule.target or rule.group] = group
        end
    end
    return Copy(out)
end

local function ReadRootPath(root, path)
    local value = root
    for segment in path:gmatch("[^%.]+") do
        value = type(value) == "table" and value[segment] or nil
    end
    if value == nil then return {} end
    if type(value) ~= "table" then return nil, "setting root is not a table: " .. path end
    return Copy(value)
end

local function CaptureAppearance()
    local root, rootReason = Root()
    if not root then
        return nil, rootReason
    end
    local spec, specReason = AppearanceSpec()
    if not spec then return nil, specReason end

    local modules = {}
    for _, key in ipairs(spec.moduleKeys) do
        local value = root.ModuleDB[key]
        if type(value) == "table" then
            local copied, reason = ProjectDeclaredModule(key)
            -- A module may have a SavedVariables table before its schema has
            -- registered (or may be disabled for this login).  That must not
            -- make the whole default appearance profile disappear.  It is
            -- simply omitted until it can be exported through its declared
            -- schema; omitted fields are deliberately non-destructive when a
            -- profile is later enabled.
            if copied and not reason then
                modules[key] = copied
            end
        end
    end

    local settings = {}
    for _, path in ipairs(spec.rootPaths) do
        local copied, copyReason = ReadRootPath(root, path)
        if not copied then return nil, path .. ": " .. tostring(copyReason) end
        if path == "ui.general" then
            copied = SyncGeneralCVarsIntoExport(copied)
        end
        settings[path] = copied
    end

    return {
        modules = modules,
        root = { settings = settings },
    }
end

local function ValidateAppearance(value)
    local spec, specReason = AppearanceSpec()
    if not spec then return false, specReason end
    if type(value) ~= "table" or not Only(value, { modules = true, root = true })
        or type(value.modules) ~= "table" or type(value.root) ~= "table" then
        return false, "invalid appearance configuration"
    end
    if not Only(value.modules, spec.moduleKeySet) then
        return false, "appearance configuration contains an unknown module"
    end
    -- uiGeneral/voiceColors/Kyrakka are accepted only so existing profiles and
    -- exported strings remain readable.  New captures use root.settings.
    if not Only(value.root, { settings = true, uiGeneral = true, voiceColors = true, kyrakkaWindFirePosition = true }) then
        return false, "invalid appearance root configuration"
    end

    local state = { seen = {}, count = 0 }
    for key, moduleDB in pairs(value.modules) do
        if spec.moduleKeySet[key] ~= true or type(moduleDB) ~= "table" then
            return false, "invalid module configuration"
        end
        local ok, reason = ValidateValue(moduleDB, state, 0)
        if not ok then
            return false, key .. ": " .. tostring(reason)
        end
    end
    if value.root.settings ~= nil then
        if type(value.root.settings) ~= "table" or not Only(value.root.settings, spec.rootPathSet) then
            return false, "appearance configuration contains an unknown setting root"
        end
        for path, setting in pairs(value.root.settings) do
            if type(setting) ~= "table" then return false, "invalid setting root: " .. tostring(path) end
            local ok, reason = ValidateValue(setting, state, 0)
            if not ok then return false, path .. ": " .. tostring(reason) end
        end
    end
    for key, setting in pairs({ uiGeneral = value.root.uiGeneral, voiceColors = value.root.voiceColors, kyrakkaWindFirePosition = value.root.kyrakkaWindFirePosition }) do
        if setting ~= nil then
            local ok, reason = ValidateValue(setting, state, 0)
            if not ok then return false, key .. ": " .. tostring(reason) end
        end
    end
    return true
end

local function NewDefaultProfile()
    local appearance, reason = CaptureAppearance()
    if not appearance then
        return nil, reason
    end
    return {
        id = "default",
        name = L["默认外观"],
        appearance = appearance,
    }
end

local function EnsureStore()
    local root, rootReason = Root()
    if not root then
        return nil, rootReason
    end
    if type(root.appearanceProfiles) ~= "table" then
        root.appearanceProfiles = {}
    end
    local store = root.appearanceProfiles
    store.schema = PROFILE_SCHEMA
    if type(store.profiles) ~= "table" then
        store.profiles = {}
    end
    if type(store.profiles.default) ~= "table" then
        local profile, reason = NewDefaultProfile()
        if not profile then
            return nil, reason
        end
        store.profiles.default = profile
    end
    local activeID = Trim(store.activeProfileID)
    if type(store.profiles[activeID]) ~= "table" then
        activeID = "default"
    end
    store.activeProfileID = activeID
    return store
end

local function ProfileName(profile, fallback)
    local name = Trim(type(profile) == "table" and profile.name or "")
    if name == "" then
        name = fallback or L["外观配置"]
    end
    -- Default names created before locale support were persisted in the
    -- SavedVariables as Chinese.  They are system labels rather than user
    -- names, so resolve their display value at render/export/import time.
    -- Any other profile name stays exactly as the user entered it.
    if name == "默认外观" or name == "Default Appearance" then
        name = L["默认外观"]
    elseif name == "导入的外观" or name == "Imported Appearance" then
        name = L["导入的外观"]
    end
    return name:sub(1, 80)
end

local function SaveActiveProfile()
    local store, storeReason = EnsureStore()
    if not store then
        return false, storeReason
    end
    local appearance, reason = CaptureAppearance()
    if not appearance then
        return false, reason
    end
    local profile = store.profiles[store.activeProfileID]
    if type(profile) ~= "table" then
        return false, "active appearance profile is unavailable"
    end
    profile.id = store.activeProfileID
    profile.name = ProfileName(profile, store.activeProfileID)
    profile.appearance = appearance
    return true
end

local function MergeSettings(target, source)
    if type(target) ~= "table" or type(source) ~= "table" then return false, "invalid setting root" end
    for key, value in pairs(source) do
        if type(value) == "table" and type(target[key]) == "table" then
            local ok, reason = MergeSettings(target[key], value)
            if not ok then return false, reason end
        else
            local copied, reason = Copy(value)
            if reason then return false, reason end
            target[key] = copied
        end
    end
    return true
end

local function EnsureRootPath(root, path)
    local target = root
    for segment in path:gmatch("[^%.]+") do
        if type(target[segment]) ~= "table" then target[segment] = {} end
        target = target[segment]
    end
    return target
end

local function ApplyAppearance(appearance)
    local valid, reason = ValidateAppearance(appearance)
    if not valid then
        return false, reason
    end
    local root, rootReason = Root()
    if not root then
        return false, rootReason
    end

    -- Copy every selected value before touching live settings.  A malformed
    -- profile therefore cannot leave a partly-applied visual setup behind.
    local prepared, copyReason = Copy(appearance)
    if not prepared then
        return false, copyReason
    end
    local spec, specReason = AppearanceSpec()
    if not spec then return false, specReason end

    for _, key in ipairs(spec.moduleKeys) do
        local source = prepared.modules[key]
        local target = root.ModuleDB[key]
        if source ~= nil and type(target) == "table" then
            for childKey in pairs(target) do
                target[childKey] = nil
            end
            for childKey, childValue in pairs(source) do
                target[childKey] = childValue
            end
        elseif source ~= nil then
            root.ModuleDB[key] = source
        end
    end

    -- Settings roots merge rather than clear: new profile fields apply, while
    -- unknown future fields and all Boss/trash data remain untouched.
    for path, source in pairs(prepared.root.settings or {}) do
        local ok, mergeReason = MergeSettings(EnsureRootPath(root, path), source)
        if not ok then return false, path .. ": " .. tostring(mergeReason) end
        if path == "ui.general" then
            ApplyGeneralCVarsFromImport(source)
        end
    end

    -- Compatibility for pre-router profiles.  These are deliberately merged;
    -- their old partial root snapshots must never erase newer settings.
    if type(prepared.root.uiGeneral) == "table" then
        local ok, mergeReason = MergeSettings(EnsureRootPath(root, "ui.general"), prepared.root.uiGeneral)
        if not ok then return false, "ui.general: " .. tostring(mergeReason) end
    end
    if type(prepared.root.voiceColors) == "table" then
        local ok, mergeReason = MergeSettings(EnsureRootPath(root, "voice"), prepared.root.voiceColors)
        if not ok then return false, "voice: " .. tostring(mergeReason) end
    end
    return true
end

local function Libs()
    return LibStub and LibStub("LibSerialize", true), LibStub and LibStub("LibDeflate", true)
end

local function Encode(payload)
    local serialize, deflate = Libs()
    if not serialize or not deflate then
        return nil, "missing LibSerialize/LibDeflate"
    end
    local packed = serialize:Serialize(payload)
    if type(packed) ~= "string" then
        return nil, "serialize failed"
    end
    packed = deflate:CompressDeflate(packed)
    if type(packed) ~= "string" then
        return nil, "compress failed"
    end
    packed = deflate:EncodeForPrint(packed)
    if type(packed) ~= "string" or packed == "" then
        return nil, "encode failed"
    end
    return TRANSFER_PREFIX .. packed
end

local function Decode(raw)
    local text = Trim(raw)
    if text:sub(1, #TRANSFER_PREFIX) ~= TRANSFER_PREFIX then
        return nil, "unsupported appearance configuration prefix"
    end
    if #text > MAX_TRANSFER_LENGTH then
        return nil, "appearance configuration is too large"
    end
    local body = text:sub(#TRANSFER_PREFIX + 1)
    if body == "" then
        return nil, "empty appearance configuration"
    end
    local serialize, deflate = Libs()
    if not serialize or not deflate then
        return nil, "missing LibSerialize/LibDeflate"
    end
    local packed = deflate:DecodeForPrint(body)
    if type(packed) ~= "string" then
        return nil, "decode failed"
    end
    packed = deflate:DecompressDeflate(packed)
    if type(packed) ~= "string" then
        return nil, "decompress failed"
    end
    local ok, payload = serialize:Deserialize(packed)
    if ok ~= true or type(payload) ~= "table" then
        return nil, "deserialize failed"
    end
    return payload
end

local function ValidateTransfer(payload)
    if type(payload) ~= "table"
        or not Only(payload, { version = true, payloadType = true, profile = true })
        or tonumber(payload.version) ~= TRANSFER_VERSION
        or payload.payloadType ~= "exboss_appearance_modules"
        or type(payload.profile) ~= "table"
        or not Only(payload.profile, { name = true, appearance = true })
        or type(payload.profile.name) ~= "string" then
        return nil, "unsupported appearance configuration payload"
    end
    local valid, reason = ValidateAppearance(payload.profile.appearance)
    if not valid then
        return nil, reason
    end
    local copied, copyReason = Copy(payload.profile.appearance)
    if not copied then
        return nil, copyReason
    end
    return { name = ProfileName({ name = payload.profile.name }, L["导入的外观"]), appearance = copied }
end

function Profiles:GetModuleKeys()
    local spec = AppearanceSpec()
    if not spec then return {} end
    local out = {}
    for i, key in ipairs(spec.moduleKeys) do
        out[i] = key
    end
    return out
end

function Profiles:GetProfileItems()
    local store = EnsureStore()
    if not store then
        return {}
    end
    local out = {}
    for id, profile in pairs(store.profiles) do
        if type(profile) == "table" and type(profile.appearance) == "table" then
            out[#out + 1] = { ProfileName(profile, id), id }
        end
    end
    table.sort(out, function(left, right)
        if left[2] == "default" then return true end
        if right[2] == "default" then return false end
        return tostring(left[1]) < tostring(right[1])
    end)
    return out
end

function Profiles:GetActiveProfileID()
    local store = EnsureStore()
    return store and store.activeProfileID or nil
end

function Profiles:GetActiveProfileName()
    local store = EnsureStore()
    local profile = store and store.profiles[store.activeProfileID] or nil
    return profile and ProfileName(profile, store.activeProfileID) or nil
end

function Profiles:IsProfileNameAvailable(name, exceptID)
    local store = EnsureStore()
    local requested = Trim(name)
    if not store or requested == "" then return false end
    local ignoredID = Trim(exceptID)
    for id, profile in pairs(store.profiles) do
        if id ~= ignoredID and ProfileName(profile, id) == requested then
            return false
        end
    end
    return true
end

function Profiles:ExportActiveProfileString()
    local profile, reason = self:GetActiveProfilePayload()
    if not profile then return nil, reason end
    return Encode({
        version = TRANSFER_VERSION,
        payloadType = "exboss_appearance_modules",
        profile = profile,
    })
end

-- Older/inactive profiles can predate a route root (or have been created by
-- the short-lived router build that emitted root.settings = {}).  They must
-- never export an empty settings section merely because selecting a profile
-- other than the active one does not run SaveActiveProfile.  Fill only absent
-- roots from the live capture; existing profile roots remain authoritative.
local function HydrateMissingAppearanceRoots(appearance)
    if type(appearance) ~= "table" or type(appearance.root) ~= "table" then
        return false, "invalid appearance configuration"
    end
    local current, captureReason = CaptureAppearance()
    if not current then return false, captureReason end
    local currentRoots = current.root and current.root.settings
    if type(currentRoots) ~= "table" then return false, "current appearance settings are unavailable" end

    local root = appearance.root
    if type(root.settings) ~= "table" then root.settings = {} end
    for path, value in pairs(currentRoots) do
        if root.settings[path] == nil then
            local copied, copyReason = Copy(value)
            if copyReason then return false, path .. ": " .. tostring(copyReason) end
            root.settings[path] = copied
        end
    end
    return true
end

-- The combined Boss transfer uses this typed payload directly.  Keeping the
-- codec here private means it cannot accidentally package unrelated settings.
function Profiles:GetProfilePayload(profileID)
    local store = EnsureStore()
    if not store then return nil, "appearance profile store is unavailable" end
    local id = profileID == nil and store.activeProfileID or Trim(profileID)
    if id == store.activeProfileID then
        local ok, reason = SaveActiveProfile()
        if not ok then return nil, reason end
        store = EnsureStore()
    end
    local profile = store and store.profiles[id] or nil
    if type(profile) ~= "table" then return nil, "active appearance profile is unavailable" end
    local appearance, copyReason = Copy(profile.appearance)
    if not appearance then return nil, copyReason end
    local hydrated, hydrateReason = HydrateMissingAppearanceRoots(appearance)
    if not hydrated then return nil, hydrateReason end
    return { name = ProfileName(profile, id), appearance = appearance }
end

function Profiles:GetActiveProfilePayload()
    return self:GetProfilePayload(nil)
end

function Profiles:DecodeImportString(raw)
    local payload, reason = Decode(raw)
    if not payload then
        return nil, reason
    end
    return ValidateTransfer(payload)
end

function Profiles:GetImportSummary(decoded)
    if type(decoded) ~= "table" or type(decoded.appearance) ~= "table" then
        return nil
    end
    local spec = AppearanceSpec()
    if not spec then return nil end
    local moduleCount = 0
    for key in pairs(decoded.appearance.modules or {}) do
        if spec.moduleKeySet[key] then
            moduleCount = moduleCount + 1
        end
    end
    return { name = ProfileName(decoded, L["导入的外观"]), moduleCount = moduleCount }
end

function Profiles:ValidateProfilePayload(decoded)
    if type(decoded) ~= "table" or type(decoded.name) ~= "string" then
        return nil, "invalid appearance configuration"
    end
    local valid, reason = ValidateAppearance(decoded.appearance)
    if not valid then
        return nil, reason
    end
    local copied, copyReason = Copy(decoded.appearance)
    if not copied then
        return nil, copyReason
    end
    return { name = ProfileName(decoded, L["导入的外观"]), appearance = copied }
end

function Profiles:ImportProfilePayload(decoded)
    local normalized, validationReason = self:ValidateProfilePayload(decoded)
    if not normalized then return false, validationReason end
    local copied = normalized.appearance
    local store, storeReason = EnsureStore()
    if not store then
        return false, storeReason
    end
    if not self:IsProfileNameAvailable(normalized.name) then
        return false, "appearance profile name already exists"
    end
    local index, id = 1, "imported-appearance-1"
    while store.profiles[id] ~= nil do
        index = index + 1
        id = "imported-appearance-" .. index
    end
    store.profiles[id] = {
        id = id,
        name = normalized.name,
        appearance = copied,
    }
    return true, id
end

function Profiles:ImportDecodedProfile(decoded)
    return self:ImportProfilePayload(decoded)
end

function Profiles:ActivateProfile(profileID)
    local id = Trim(profileID)
    local store, storeReason = EnsureStore()
    if not store then
        return false, storeReason
    end
    local profile = store.profiles[id]
    if type(profile) ~= "table" then
        return false, "appearance profile not found"
    end
    local valid, reason = ValidateAppearance(profile.appearance)
    if not valid then
        return false, reason
    end
    if id == store.activeProfileID then
        return true, false
    end
    local saved, saveReason = SaveActiveProfile()
    if not saved then
        return false, saveReason
    end
    local applied, applyReason = ApplyAppearance(profile.appearance)
    if not applied then
        return false, applyReason
    end
    store.activeProfileID = id
    return true, true
end
