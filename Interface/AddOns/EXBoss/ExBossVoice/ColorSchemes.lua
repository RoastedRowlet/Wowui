---@diagnostic disable: undefined-global

ExBoss.Voice = ExBoss.Voice or {}
ExBoss.Voice.ColorSchemes = ExBoss.Voice.ColorSchemes or {}
local CS = ExBoss.Voice.ColorSchemes

local FIXED_ORDER = { "tank", "heal", "target", "cooldown", "mechanic" }
local FIXED_DEFAULTS = {
    tank     = { name = "坦克方案", r = 0xC6/255, g = 0x9B/255, b = 0x6C/255 },  -- #C69B6C
    heal     = { name = "治疗方案", r = 0x5F/255, g = 0xFF/255, b = 0x9D/255 },  -- #5FFF9D
    target   = { name = "点名方案", r = 0xFF/255, g = 0x3B/255, b = 0x30/255 },  -- #FF3B30
    cooldown = { name = "其他方案", r = 1, g = 1, b = 1 },  -- #FFFFFF
    mechanic = { name = "特殊技能", r = 0xDA/255, g = 0x5B/255, b = 0xFF/255 },  -- #DA5BFF
}
local CUSTOM_KEY = "__custom"
local EXTRA_CUSTOM_PREFIX = "__extra_custom_"
local EXTRA_CUSTOM_COUNT = 3
local EXTRA_CUSTOM_DEFAULTS = {
    [1] = { name = "额外方案1", r = 0.35, g = 0.72, b = 1.00 },
    [2] = { name = "额外方案2", r = 1.00, g = 0.58, b = 0.25 },
    [3] = { name = "额外方案3", r = 0.78, g = 0.64, b = 1.00 },
}

local LEGACY_COOLDOWN_COLOR = { r = 0xA5/255, g = 0xAF/255, b = 0xA2/255 }

local function IsLegacyCooldownColor(row)
    if type(row) ~= "table" then return false end
    local epsilon = 0.00001
    return math.abs((tonumber(row.r) or -1) - LEGACY_COOLDOWN_COLOR.r) < epsilon
        and math.abs((tonumber(row.g) or -1) - LEGACY_COOLDOWN_COLOR.g) < epsilon
        and math.abs((tonumber(row.b) or -1) - LEGACY_COOLDOWN_COLOR.b) < epsilon
end

local function GetLocaleTable()
    if ExBoss and ExBoss.Locale and ExBoss.Locale.Get then
        local tbl = ExBoss.Locale:Get()
        if type(tbl) == "table" then
            return tbl
        end
    end
    return ExBoss and ExBoss.L or nil
end

local function LT(key)
    local tbl = GetLocaleTable()
    local value = tbl and tbl[key]
    if type(value) == "string" and value ~= "" then
        return value
    end
    return key
end

local function IsDefaultDisplayName(name, ...)
    local current = tostring(name or "")
    if current == "" then
        return true
    end
    for i = 1, select("#", ...) do
        local candidate = tostring(select(i, ...) or "")
        if candidate ~= "" and current == candidate then
            return true
        end
    end
    return false
end

local function Clamp01(v, fallback)
    local n = tonumber(v)
    if not n then return fallback or 0 end
    if n < 0 then return 0 end
    if n > 1 then return 1 end
    return n
end

local function RGBToHex(r, g, b)
    local rr = math.floor(Clamp01(r, 1) * 255 + 0.5)
    local gg = math.floor(Clamp01(g, 1) * 255 + 0.5)
    local bb = math.floor(Clamp01(b, 1) * 255 + 0.5)
    return string.format("%02x%02x%02x", rr, gg, bb)
end

local function ParseExtraCustomIndex(scheme)
    local s = tostring(scheme or "")
    if s:sub(1, #EXTRA_CUSTOM_PREFIX) ~= EXTRA_CUSTOM_PREFIX then
        return nil
    end
    local idx = tonumber(s:sub(#EXTRA_CUSTOM_PREFIX + 1))
    if not idx or idx < 1 or idx > EXTRA_CUSTOM_COUNT then
        return nil
    end
    return idx
end

function CS.EnsureDB()
    EXBOSS12S2 = EXBOSS12S2 or {}
    EXBOSS12S2.voice = EXBOSS12S2.voice or {}
    local db = EXBOSS12S2.voice

    db.colorSchemes = type(db.colorSchemes) == "table" and db.colorSchemes or {}
    db.customColors = type(db.customColors) == "table" and db.customColors or {}
    db.extraCustomColors = type(db.extraCustomColors) == "table" and db.extraCustomColors or {}

    for _, key in ipairs(FIXED_ORDER) do
        local def = FIXED_DEFAULTS[key]
        local row = db.colorSchemes[key]
        if type(row) ~= "table" then
            row = {}
            db.colorSchemes[key] = row
        end
        row.name = (type(row.name) == "string" and row.name ~= "") and row.name or def.name
        -- Upgrade only the old stock grey.  Any distinct player-selected
        -- colour remains a deliberate user setting.
        if key == "cooldown" and IsLegacyCooldownColor(row) then
            row.r, row.g, row.b = def.r, def.g, def.b
        else
            row.r = Clamp01(row.r, def.r)
            row.g = Clamp01(row.g, def.g)
            row.b = Clamp01(row.b, def.b)
        end
    end

    local c1 = db.customColors[1]
    if type(c1) ~= "table" then
        c1 = {}
        db.customColors[1] = c1
    end
    c1.name = type(c1.name) == "string" and c1.name or "自定义方案"
    c1.r = Clamp01(c1.r, 1)
    c1.g = Clamp01(c1.g, 0.82)
    c1.b = Clamp01(c1.b, 0.25)

    for i = 1, EXTRA_CUSTOM_COUNT do
        local def = EXTRA_CUSTOM_DEFAULTS[i]
        local row = db.extraCustomColors[i]
        if type(row) ~= "table" then
            row = {}
            db.extraCustomColors[i] = row
        end
        row.enabled = (row.enabled == true)
        row.name = type(row.name) == "string" and row.name or def.name
        row.r = Clamp01(row.r, def.r)
        row.g = Clamp01(row.g, def.g)
        row.b = Clamp01(row.b, def.b)
    end

    return db
end

function CS.GetFixedOrder()
    return FIXED_ORDER
end

function CS.GetFixedDefaults()
    return FIXED_DEFAULTS
end

function CS.GetCustomKey()
    return CUSTOM_KEY
end

function CS.GetExtraCustomCount()
    return EXTRA_CUSTOM_COUNT
end

function CS.GetExtraCustomKey(index)
    local idx = tonumber(index)
    if not idx or idx < 1 or idx > EXTRA_CUSTOM_COUNT then
        return nil
    end
    return EXTRA_CUSTOM_PREFIX .. tostring(idx)
end

function CS.GetExtraCustomSlot(index)
    local idx = tonumber(index)
    if not idx or idx < 1 or idx > EXTRA_CUSTOM_COUNT then
        return nil
    end
    local db = CS.EnsureDB()
    return db.extraCustomColors and db.extraCustomColors[idx] or nil
end

function CS.GetSchemeDisplayName(scheme)
    if scheme == CUSTOM_KEY then
        return CS.GetCustomName()
    end
    local extraIdx = ParseExtraCustomIndex(scheme)
    if extraIdx then
        local row = CS.GetExtraCustomSlot(extraIdx)
        local def = EXTRA_CUSTOM_DEFAULTS[extraIdx]
        local fallback = def and def.name or ("额外方案" .. tostring(extraIdx))
        local localized = LT("额外方案") .. tostring(extraIdx)
        if type(row) == "table" and type(row.name) == "string" and row.name ~= "" and not IsDefaultDisplayName(row.name, fallback, localized) then
            return row.name
        end
        return localized
    end

    local db = CS.EnsureDB()
    local row = db.colorSchemes and db.colorSchemes[scheme]
    local def = FIXED_DEFAULTS[scheme]
    local localized = def and LT(def.name) or tostring(scheme or "")
    if type(row) == "table" and type(row.name) == "string" and row.name ~= "" and not IsDefaultDisplayName(row.name, def and def.name, localized) then
        return row.name
    end
    return localized
end

function CS.GetSchemeColor(scheme)
    if scheme == CUSTOM_KEY then
        return CS.GetCustomColor()
    end
    local extraIdx = ParseExtraCustomIndex(scheme)
    if extraIdx then
        local row = CS.GetExtraCustomSlot(extraIdx)
        local def = EXTRA_CUSTOM_DEFAULTS[extraIdx]
        if type(row) == "table" then
            return Clamp01(row.r, def and def.r or 1), Clamp01(row.g, def and def.g or 1), Clamp01(row.b, def and def.b or 1)
        end
        if def then
            return def.r, def.g, def.b
        end
        return 1, 1, 1
    end

    local db = CS.EnsureDB()
    local row = db.colorSchemes and db.colorSchemes[scheme]
    local def = FIXED_DEFAULTS[scheme]
    if type(row) == "table" then
        return Clamp01(row.r, def and def.r or 1), Clamp01(row.g, def and def.g or 1), Clamp01(row.b, def and def.b or 1)
    end
    if def then
        return def.r, def.g, def.b
    end
    return 1, 1, 1
end

function CS.GetCustomColor()
    local db = CS.EnsureDB()
    local row = db.customColors and db.customColors[1]
    if type(row) ~= "table" then
        return 1, 0.82, 0.25
    end
    return Clamp01(row.r, 1), Clamp01(row.g, 0.82), Clamp01(row.b, 0.25)
end

function CS.GetCustomName()
    local db = CS.EnsureDB()
    local row = db.customColors and db.customColors[1]
    local localized = LT("自定义方案")
    if type(row) == "table" and type(row.name) == "string" and row.name ~= "" and not IsDefaultDisplayName(row.name, "自定义方案", localized) then
        return row.name
    end
    return localized
end

function CS.BuildDropdownItems()
    local items = {}
    for _, key in ipairs(FIXED_ORDER) do
        local r, g, b = CS.GetSchemeColor(key)
        local hex = RGBToHex(r, g, b)
        items[#items + 1] = { "|cff" .. hex .. CS.GetSchemeDisplayName(key) .. "|r", key }
    end
    local cr, cg, cb = CS.GetCustomColor()
    local ch = RGBToHex(cr, cg, cb)
    items[#items + 1] = { "|cff" .. ch .. CS.GetCustomName() .. "|r", CUSTOM_KEY }

    local db = CS.EnsureDB()
    for i = 1, EXTRA_CUSTOM_COUNT do
        local row = db.extraCustomColors and db.extraCustomColors[i]
        if type(row) == "table" and row.enabled == true then
            local key = CS.GetExtraCustomKey(i)
            local r, g, b = CS.GetSchemeColor(key)
            local hex = RGBToHex(r, g, b)
            items[#items + 1] = { "|cff" .. hex .. CS.GetSchemeDisplayName(key) .. "|r", key }
        end
    end
    return items
end

function CS.NormalizeSchemeKey(scheme)
    local s = tostring(scheme or "")
    for _, key in ipairs(FIXED_ORDER) do
        if s == key then
            return s
        end
    end
    if s == CUSTOM_KEY then
        return CUSTOM_KEY
    end
    local extraIdx = ParseExtraCustomIndex(s)
    if extraIdx then
        return CS.GetExtraCustomKey(extraIdx)
    end
    return nil
end

function CS.NormalizeEventColorConfig(colorCfg)
    if type(colorCfg) ~= "table" then
        return nil
    end
    if colorCfg.enabled == nil then
        colorCfg.enabled = true
    end

    local scheme = CS.NormalizeSchemeKey(colorCfg.scheme)
    local hasRGB = (colorCfg.r ~= nil and colorCfg.g ~= nil and colorCfg.b ~= nil)
    local useCustom = (colorCfg.useCustom == true)
    if colorCfg.useCustom == nil then
        useCustom = (scheme == CUSTOM_KEY) or (scheme == nil and hasRGB)
    end

    if useCustom then
        local cr, cg, cb = CS.GetCustomColor()
        colorCfg.useCustom = true
        colorCfg.scheme = CUSTOM_KEY
        colorCfg.r = Clamp01(colorCfg.r, cr)
        colorCfg.g = Clamp01(colorCfg.g, cg)
        colorCfg.b = Clamp01(colorCfg.b, cb)
    else
        colorCfg.useCustom = false
        colorCfg.scheme = scheme or "cooldown"
    end
    return colorCfg
end

function CS.ResolveEventColor(colorCfg)
    if type(colorCfg) ~= "table" or colorCfg.enabled == false then
        return nil
    end

    local cfg = CS.NormalizeEventColorConfig(colorCfg)
    if not cfg then
        return nil
    end

    if cfg.useCustom == true or cfg.scheme == CUSTOM_KEY then
        return Clamp01(cfg.r, 1), Clamp01(cfg.g, 0.82), Clamp01(cfg.b, 0.25)
    end
    return CS.GetSchemeColor(cfg.scheme)
end
