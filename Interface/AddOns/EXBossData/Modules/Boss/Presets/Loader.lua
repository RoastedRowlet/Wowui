---@diagnostic disable: undefined-global
-- Load-time Author registry.  Authors are read-only inputs, never SavedVariables.

_G.EXBossData = _G.EXBossData or {}
_G.EXBOSS_AUTHORS = _G.EXBOSS_AUTHORS or { mplus = {}, raid = {} }

local function Copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, child in pairs(value) do out[key] = Copy(child) end
    return out
end

local function RegisterAuthor(artifact, builtin)
    if type(artifact) ~= "table" or (artifact.category ~= "mplus" and artifact.category ~= "raid")
        or type(artifact.id) ~= "string" or artifact.id == "" or type(artifact.values) ~= "table" then
        return false, "invalid author artifact"
    end
    local root = _G.EXBOSS_AUTHORS
    local category = root[artifact.category]
    if type(category) ~= "table" then
        category = {}
        root[artifact.category] = category
    end
    if category[artifact.id] ~= nil then return false, "author id already registered" end
    category[artifact.id] = {
        id = artifact.id,
        category = artifact.category,
        name = type(artifact.name) == "string" and artifact.name or artifact.id,
        author = type(artifact.author) == "string" and artifact.author or "",
        builtin = builtin == true,
        values = Copy(artifact.values),
    }
    return true, artifact.id
end

-- EXBoss bundled preset files use this explicit entry.  External Author
-- addons use RegisterAuthor; the data shape is the same, only provenance is
-- deliberate and never guessed from an ID or file path.
function _G.EXBossData.RegisterBuiltinAuthor(artifact)
    return RegisterAuthor(artifact, true)
end

function _G.EXBossData.RegisterAuthor(artifact)
    return RegisterAuthor(artifact, false)
end
