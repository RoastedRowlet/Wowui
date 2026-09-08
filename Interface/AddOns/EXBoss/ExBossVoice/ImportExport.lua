---@diagnostic disable: undefined-global
-- Portable Boss transfers always package Author values with that Author's
-- private User override. Version 7 carries role assignments so the receiver
-- can choose exactly which imported pairs become active.

ExBoss.Voice = ExBoss.Voice or {}
ExBoss.Voice.ImportExport = ExBoss.Voice.ImportExport or {}
local IE = ExBoss.Voice.ImportExport

local PREFIX = "EXBXC:"
local LEGACY_VERSION, LEGACY_TYPE = 6, "exboss_author_user_values"
local BUNDLE_VERSION, BUNDLE_TYPE = 7, "exboss_bundle"
local MAX_TRANSFER_LENGTH = 1000000
local MAX_VALUE_DEPTH, MAX_VALUE_COUNT = 45, 100000

local SLOT_SET = {
    mplus = { mplus_tank = true, mplus_dps = true, mplus_heal = true },
    raid = { raid_tank = true, raid_dps = true, raid_heal = true },
}

local function Trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function IsFiniteNumber(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function Copy(value, seen)
    local kind = type(value)
    if kind == "nil" or kind == "boolean" or kind == "string" then return value end
    if kind == "number" then return value end
    if kind ~= "table" then return nil, "unsupported value type: " .. kind end
    seen = seen or {}
    if seen[value] then return nil, "cyclic configuration table" end
    seen[value] = true
    local out = {}
    for key, child in pairs(value) do
        local copied, reason = Copy(child, seen)
        if reason then seen[value] = nil; return nil, reason end
        out[key] = copied
    end
    seen[value] = nil
    return out
end

local function Only(value, allowed)
    if type(value) ~= "table" then return false end
    for key in pairs(value) do if allowed[key] ~= true then return false end end
    return true
end

local function IsArray(value)
    if type(value) ~= "table" then return false end
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then return false end
        count = count + 1
    end
    return count == #value
end

local function ValidateValue(value, state, depth)
    local kind = type(value)
    if kind == "nil" or kind == "boolean" or kind == "string" then return true end
    if kind == "number" then return IsFiniteNumber(value), "unsupported numeric value" end
    if kind ~= "table" then return false, "unsupported value type: " .. kind end
    if depth >= MAX_VALUE_DEPTH then return false, "configuration nesting is too deep" end
    if state.seen[value] then return false, "cyclic configuration table" end
    state.count = state.count + 1
    if state.count > MAX_VALUE_COUNT then return false, "configuration contains too many values" end
    state.seen[value] = true
    for key, child in pairs(value) do
        local keyKind = type(key)
        if keyKind ~= "string" and keyKind ~= "number" then
            state.seen[value] = nil; return false, "unsupported configuration key"
        end
        if keyKind == "number" and not IsFiniteNumber(key) then
            state.seen[value] = nil; return false, "unsupported numeric key"
        end
        local ok, reason = ValidateValue(child, state, depth + 1)
        if not ok then state.seen[value] = nil; return false, reason end
    end
    state.seen[value] = nil
    return true
end

local function Libs()
    return LibStub and LibStub("LibSerialize", true), LibStub and LibStub("LibDeflate", true)
end

local function Encode(payload)
    local serialize, deflate = Libs()
    if not serialize or not deflate then return nil, "missing LibSerialize/LibDeflate" end
    local packed = serialize:Serialize(payload)
    if type(packed) ~= "string" then return nil, "serialize failed" end
    packed = deflate:CompressDeflate(packed)
    if type(packed) ~= "string" then return nil, "compress failed" end
    packed = deflate:EncodeForPrint(packed)
    if type(packed) ~= "string" or packed == "" then return nil, "encode failed" end
    return PREFIX .. packed
end

local function Decode(raw)
    local text = Trim(raw)
    if text:sub(1, #PREFIX) ~= PREFIX then return nil, "unsupported configuration prefix" end
    if #text > MAX_TRANSFER_LENGTH then return nil, "configuration is too large" end
    local body = text:sub(#PREFIX + 1)
    if body == "" or body:sub(1, 4) == "RAW:" then return nil, "invalid configuration payload" end
    local serialize, deflate = Libs()
    if not serialize or not deflate then return nil, "missing LibSerialize/LibDeflate" end
    local packed = deflate:DecodeForPrint(body)
    if type(packed) ~= "string" then return nil, "decode failed" end
    packed = deflate:DecompressDeflate(packed)
    if type(packed) ~= "string" then return nil, "decompress failed" end
    local valid, payload = serialize:Deserialize(packed)
    if valid ~= true or type(payload) ~= "table" then return nil, "deserialize failed" end
    return payload
end

local function ValidateAuthorUserPair(pair, state)
    if not Only(pair, { id = true, author = true, user = true })
        or type(pair.id) ~= "string" or Trim(pair.id) == ""
        or not Only(pair.author, { id = true, name = true, author = true, values = true })
        or not Only(pair.user, { values = true })
        or type(pair.author.id) ~= "string" or Trim(pair.author.id) == ""
        or type(pair.author.name) ~= "string" or type(pair.author.author) ~= "string"
        or type(pair.author.values) ~= "table" or type(pair.user.values) ~= "table" then
        return false, "invalid Author + User configuration pair"
    end
    local ok, reason = ValidateValue(pair.author.values, state, 0)
    if not ok then return false, "Author: " .. tostring(reason) end
    ok, reason = ValidateValue(pair.user.values, state, 0)
    if not ok then return false, "User: " .. tostring(reason) end
    return true
end

local function ValidateLegacy(payload)
    if not Only(payload, { version = true, payloadType = true, profile = true })
        or tonumber(payload.version) ~= LEGACY_VERSION or payload.payloadType ~= LEGACY_TYPE
        or type(payload.profile) ~= "table"
        or not Only(payload.profile, { category = true, author = true, user = true })
        or (payload.profile.category ~= "mplus" and payload.profile.category ~= "raid") then
        return nil, "unsupported Author + User configuration payload"
    end
    local profile = payload.profile
    local synthetic = { id = "legacy", author = profile.author, user = profile.user }
    local ok, reason = ValidateAuthorUserPair(synthetic, { seen = {}, count = 0 })
    if not ok then return nil, reason end
    local copy, copyReason = Copy(profile)
    if not copy then return nil, copyReason end
    return copy
end

local function ValidateScene(category, scene, state)
    if not Only(scene, { category = true, pairs = true, assignments = true })
        or scene.category ~= category or not IsArray(scene.pairs) or type(scene.assignments) ~= "table" then
        return nil, "invalid " .. category .. " configuration scene"
    end
    local pairIDs = {}
    for _, pair in ipairs(scene.pairs) do
        local ok, reason = ValidateAuthorUserPair(pair, state)
        if not ok or pairIDs[pair.id] then return nil, reason or "duplicate configuration pair" end
        pairIDs[pair.id] = true
    end
    for slot, pairID in pairs(scene.assignments) do
        if SLOT_SET[category][slot] ~= true or type(pairID) ~= "string" or pairIDs[pairID] ~= true then
            return nil, "invalid role assignment"
        end
    end
    return true
end

local function ValidateBundle(payload)
    if not Only(payload, { version = true, payloadType = true, name = true, appearance = true, scenes = true })
        or tonumber(payload.version) ~= BUNDLE_VERSION or payload.payloadType ~= BUNDLE_TYPE
        or type(payload.scenes) ~= "table" then
        return nil, "unsupported combined configuration payload"
    end
    if payload.name ~= nil and (type(payload.name) ~= "string" or Trim(payload.name) == "") then
        return nil, "invalid configuration package name"
    end
    if payload.appearance == nil and next(payload.scenes) == nil then return nil, "configuration payload is empty" end
    local normalizedAppearance
    if payload.appearance ~= nil then
        local profiles = ExBoss and ExBoss.AppearanceProfiles
        if type(profiles) ~= "table" or type(profiles.ValidateProfilePayload) ~= "function" then
            return nil, "appearance profile import unavailable"
        end
        local appearanceReason
        normalizedAppearance, appearanceReason = profiles:ValidateProfilePayload(payload.appearance)
        if not normalizedAppearance then return nil, appearanceReason end
    end
    local state = { seen = {}, count = 0 }
    for category, scene in pairs(payload.scenes) do
        if category ~= "mplus" and category ~= "raid" then return nil, "unknown configuration scene" end
        local ok, reason = ValidateScene(category, scene, state)
        if not ok then return nil, reason end
    end
    local copy, copyReason = Copy(payload)
    if not copy then return nil, copyReason end
    -- System profile names (notably the default appearance) are localized by
    -- AppearanceProfiles.  Keep the normalized display name in decoded
    -- bundles so the import form can prefill it in the receiver's language.
    if normalizedAppearance then
        copy.appearance = normalizedAppearance
    end
    return copy
end

local function GetExportLayers(category, configID, authorID)
    local api = _G.EXBossData
    if type(api) ~= "table" or type(api.ExportUserConfiguration) ~= "function"
        or type(api.ExportAuthorConfiguration) ~= "function" then
        return nil, nil, "configuration export unavailable"
    end
    local userValues, reason = api.ExportUserConfiguration(category, configID)
    if type(userValues) ~= "table" then return nil, nil, reason or "user configuration not found" end
    authorID = Trim(authorID)
    if authorID == "" and type(api.GetCurrentConfiguration) == "function" then
        local context = api.GetCurrentConfiguration(category)
        if type(context) == "table" and context.userID == configID then authorID = Trim(context.authorID) end
    end
    if authorID == "" then return nil, nil, "active Author configuration required for this User configuration" end
    local author
    author, reason = api.ExportAuthorConfiguration(category, authorID)
    if type(author) ~= "table" then return nil, nil, reason or "author configuration not found" end
    return author, userValues
end

-- Legacy single-pair exports remain available for Wago and old integrations.
function IE:ExportUserConfigurationString(category, configID, authorID)
    category, configID = Trim(category), Trim(configID)
    local author, userValues, reason = GetExportLayers(category, configID, authorID)
    if not author then return nil, reason end
    return Encode({ version = LEGACY_VERSION, payloadType = LEGACY_TYPE,
        profile = { category = category, author = author, user = { values = userValues } } })
end

function IE:ExportAuthorUserPairString(category, pair)
    category = Trim(category)
    local profile, reason = ValidateLegacy({
        version = LEGACY_VERSION,
        payloadType = LEGACY_TYPE,
        profile = { category = category, author = type(pair) == "table" and pair.author, user = type(pair) == "table" and pair.user },
    })
    if not profile then return nil, reason end
    return Encode({ version = LEGACY_VERSION, payloadType = LEGACY_TYPE, profile = profile })
end

function IE:DecodeUserConfigurationPayload(raw)
    local payload, reason = Decode(raw)
    if not payload then return nil, reason end
    local profile
    profile, reason = ValidateLegacy(payload)
    if not profile then return nil, reason end
    return { version = LEGACY_VERSION, payloadType = LEGACY_TYPE, profile = profile }
end

function IE:GetUserConfigurationSummary(payload)
    local profile, reason = ValidateLegacy(payload)
    if not profile then return nil, reason end
    return { category = profile.category, authorID = profile.author.id, authorName = profile.author.name }
end

-- Old strings import the whole pair but have no role assignment, so they never
-- change the receiver's active Author selection automatically.
function IE:ImportUserConfigurationPayload(payload, importedName)
    local profile, reason = ValidateLegacy(payload)
    if not profile then return false, reason end
    local boss = ExBoss and ExBoss.BossConfig
    if type(boss) ~= "table" or type(boss.ImportAuthorUserPair) ~= "function" then
        return false, "Author + User configuration import unavailable"
    end
    return boss:ImportAuthorUserPair(profile.category, { author = profile.author, user = profile.user }, importedName)
end

function IE:ImportUserConfigurationString(raw)
    local payload, reason = self:DecodeUserConfigurationPayload(raw)
    if not payload then return false, reason end
    return self:ImportUserConfigurationPayload(payload)
end

function IE:ExportBundle(options)
    options = type(options) == "table" and options or {}
    local boss = ExBoss and ExBoss.BossConfig
    local bundle = { version = BUNDLE_VERSION, payloadType = BUNDLE_TYPE, scenes = {} }
    local name = Trim(options.name)
    if name ~= "" then bundle.name = name end
    if options.appearanceProfileID then
        local profiles = ExBoss and ExBoss.AppearanceProfiles
        if type(profiles) ~= "table" or type(profiles.GetProfilePayload) ~= "function" then
            return nil, "appearance profile export unavailable"
        end
        local profile, reason = profiles:GetProfilePayload(options.appearanceProfileID)
        if not profile then return nil, reason end
        bundle.appearance = profile
    end
    for _, category in ipairs({ "mplus", "raid" }) do
        if options[category] == true then
            if type(boss) ~= "table" or type(boss.BuildSceneTransfer) ~= "function" then
                return nil, "Boss configuration export unavailable"
            end
            local scene, reason = boss:BuildSceneTransfer(category)
            if not scene then return nil, reason end
            bundle.scenes[category] = scene
        end
    end
    if bundle.appearance == nil and next(bundle.scenes) == nil then return nil, "select at least one configuration" end
    local valid, reason = ValidateBundle(bundle)
    if not valid then return nil, reason end
    return Encode(valid)
end

function IE:DecodeTransfer(raw)
    local payload, reason = Decode(raw)
    if not payload then return nil, reason end
    if tonumber(payload.version) == BUNDLE_VERSION and payload.payloadType == BUNDLE_TYPE then
        local bundle
        bundle, reason = ValidateBundle(payload)
        if not bundle then return nil, reason end
        return { kind = "bundle", bundle = bundle }
    end
    local profile
    profile, reason = ValidateLegacy(payload)
    if not profile then return nil, reason end
    return { kind = "legacyBoss", profile = profile }
end

function IE:GetTransferSummary(decoded)
    if type(decoded) ~= "table" then return nil end
    if decoded.kind == "legacyBoss" and type(decoded.profile) == "table" then
        return { kind = "legacyBoss", category = decoded.profile.category, pairCount = 1 }
    end
    if decoded.kind ~= "bundle" or type(decoded.bundle) ~= "table" then return nil end
    local summary = { kind = "bundle", appearance = decoded.bundle.appearance, scenes = {} }
    for _, category in ipairs({ "mplus", "raid" }) do
        local scene = decoded.bundle.scenes[category]
        if type(scene) == "table" then
            summary.scenes[category] = { pairCount = #scene.pairs, assignments = scene.assignments }
        end
    end
    return summary
end
