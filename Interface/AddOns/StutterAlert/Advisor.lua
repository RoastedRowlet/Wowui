local _, ns = ...
local L     = ns.L
local DB    = ns.DB
local STATE = ns.STATE
local COLOR = ns.COLOR

local format = string.format
local floor  = math.floor
local sort   = table.sort
local concat = table.concat

local Advisor = {}
ns.Advisor = Advisor

-- Heading and muted colors for the panel text (formatting, not content).
local HEAD = { 1.00, 0.82, 0.00 }
local MUTE = { 0.60, 0.60, 0.60 }

local function hex(c)
    return format("ff%02x%02x%02x", floor(c[1] * 255 + 0.5), floor(c[2] * 255 + 0.5), floor(c[3] * 255 + 0.5))
end

local function col(c, s)
    return "|c" .. hex(c) .. s .. "|r"
end

-- Trim trailing zeros so "1.000000" reads as "1".
local function pretty(v)
    local n = tonumber(v)
    if not n then return tostring(v) end
    if n == floor(n) then return tostring(floor(n)) end
    return (format("%.2f", n):gsub("%.?0+$", ""))
end

-- ---------------------------------------------------------------------------
-- CVar access. We NEVER assume a console variable exists in this client: every
-- read is probed with pcall and returns nil if the name is unknown, so a CVar
-- that was renamed or removed simply drops out of the advice instead of erroring.
-- (Same approach AdvancedInterfaceOptions uses.)
-- ---------------------------------------------------------------------------
local GetCVarInfo = C_CVar and C_CVar.GetCVarInfo

local function readCVar(name)
    if not GetCVarInfo then return nil end
    local ok, value, default = pcall(GetCVarInfo, name)
    if not ok or value == nil then return nil end
    return value, default
end

-- Metadata per CVar. kind "slider": a higher number costs more, so we suggest
-- lowering it when it's above its default. kind "toggle": non-zero == on/costly,
-- so we suggest turning it off when it's on.
local CVAR = {
    graphicsViewDistance      = { labelKey = "CVAR_VIEW_DISTANCE",  kind = "slider" },
    graphicsEnvironmentDetail = { labelKey = "CVAR_ENV_DETAIL",     kind = "slider" },
    graphicsGroundClutter     = { labelKey = "CVAR_GROUND_CLUTTER", kind = "slider" },
    graphicsShadowQuality     = { labelKey = "CVAR_SHADOW",         kind = "slider" },
    graphicsLiquidDetail      = { labelKey = "CVAR_LIQUID",         kind = "slider" },
    graphicsSunshafts         = { labelKey = "CVAR_SUNSHAFTS",      kind = "slider" },
    graphicsParticleDensity   = { labelKey = "CVAR_PARTICLE",       kind = "slider" },
    graphicsSSAO              = { labelKey = "CVAR_SSAO",           kind = "slider" },
    graphicsDepthEffects      = { labelKey = "CVAR_DEPTH",          kind = "slider" },
    graphicsTextureResolution = { labelKey = "CVAR_TEXTURE_RES",    kind = "slider" },
    graphicsProjectedTextures = { labelKey = "CVAR_PROJECTED",      kind = "toggle" },
    graphicsSpellDensity      = { labelKey = "CVAR_SPELL_DENSITY",  kind = "slider" },
}

-- Stable display order for the "Your relevant settings" overview.
local CVAR_ORDER = {
    "graphicsViewDistance", "graphicsShadowQuality", "graphicsParticleDensity",
    "graphicsSpellDensity", "graphicsProjectedTextures", "graphicsSSAO",
    "graphicsDepthEffects", "graphicsLiquidDetail", "graphicsSunshafts",
    "graphicsEnvironmentDetail", "graphicsGroundClutter", "graphicsTextureResolution",
}

-- Which CVars to suggest, per dominant game cause (most impactful first).
local ADVICE = {
    HEADLINE_COMBAT_FX = { "graphicsSpellDensity", "graphicsParticleDensity", "graphicsProjectedTextures", "graphicsSSAO", "graphicsDepthEffects" },
    HEADLINE_SCENE     = { "graphicsParticleDensity", "graphicsProjectedTextures", "graphicsViewDistance", "graphicsEnvironmentDetail" },
    HEADLINE_STREAMING = { "graphicsViewDistance", "graphicsTextureResolution", "graphicsEnvironmentDetail", "graphicsGroundClutter" },
    HEADLINE_SUSTAINED = { "graphicsShadowQuality", "graphicsViewDistance", "graphicsLiquidDetail", "graphicsSunshafts", "graphicsSSAO" },
    HEADLINE_ENGINE    = { "graphicsViewDistance", "graphicsParticleDensity", "graphicsProjectedTextures" },
    HEADLINE_LOADING   = { "graphicsViewDistance", "graphicsTextureResolution" },
    HEADLINE_UNCLEAR   = { "graphicsViewDistance", "graphicsParticleDensity" },
    HEADLINE_GC        = {},
}

-- Plain-language intro tip per cause (non-setting advice).
local TIP = {
    HEADLINE_COMBAT_FX = "ADVISE_TIP_COMBAT_FX",
    HEADLINE_SCENE     = "ADVISE_TIP_SCENE",
    HEADLINE_STREAMING = "ADVISE_TIP_STREAMING",
    HEADLINE_SUSTAINED = "ADVISE_TIP_SUSTAINED",
    HEADLINE_ENGINE    = "ADVISE_TIP_ENGINE",
    HEADLINE_UNCLEAR   = "ADVISE_TIP_ENGINE",
    HEADLINE_GC        = "ADVISE_TIP_GC",
    HEADLINE_LOADING   = "ADVISE_TIP_LOADING",
}

-- In raids the engine uses separate RAID-prefixed graphics CVars; prefer those
-- when the player's spikes cluster in raids, falling back to the base name.
local function resolve(base, preferRaid)
    if preferRaid then
        local rname = "RAID" .. base
        local v, d = readCVar(rname)
        if v ~= nil then return rname, v, d end
    end
    local v, d = readCVar(base)
    if v ~= nil then return base, v, d end
    return nil
end

local function isElevated(meta, value, default)
    if meta.kind == "toggle" then
        return value ~= "0" and value ~= "" and value ~= "false"
    end
    local v, d = tonumber(value), tonumber(default)
    if v and d then return v > d end
    return false
end

-- ---------------------------------------------------------------------------
-- Analysis: dominant cause + where/when, from the lifetime tallies.
-- ---------------------------------------------------------------------------
local function topOf(tbl)
    local bestKey, bestN = nil, 0
    for k, n in pairs(tbl) do
        if n > bestN then bestN, bestKey = n, k end
    end
    return bestKey, bestN
end

function Advisor:Analyze()
    local t = DB.data and DB.data.totals
    if not t then return nil end
    local gc = t.gameCtx or { combat = 0, moving = 0, byCtx = {}, byZone = {} }

    local topCause, topCauseN = topOf(t.causes)
    local topCtx = topOf(gc.byCtx)
    local topZone, topZoneN = topOf(gc.byZone)

    return {
        total       = t.all,
        addon       = t.addon,
        game        = t.game,
        topCause    = topCause,
        topCauseN   = topCauseN,
        combatFrac  = (t.game > 0) and (gc.combat / t.game) or 0,
        movingFrac  = (t.game > 0) and (gc.moving / t.game) or 0,
        topCtx      = topCtx,
        topZone     = topZone,
        zoneFrac    = (t.game > 0 and topZoneN) and (topZoneN / t.game) or 0,
        raidDominant = (gc.byCtx.raid or 0) > (t.game / 2),
    }
end

-- ---------------------------------------------------------------------------
-- Build the left-column advice text (one color-coded string for the panel).
-- ---------------------------------------------------------------------------
function Advisor:BuildAdviceText()
    local lines = {}
    local function add(s) lines[#lines + 1] = s or "" end

    add(col(HEAD, L.ADVISE_WHY_HEADER))
    add("")

    local a = self:Analyze()
    if not a or a.total == 0 then
        add(L.ADVISE_VERDICT_NONE)
        return concat(lines, "\n")
    end

    -- Verdict: addons vs. the game.
    if a.addon > a.game then
        add(format(L.ADVISE_VERDICT_ADDON, a.addon, a.total))
    else
        add(format(L.ADVISE_VERDICT_GAME, a.game, a.total))
    end

    -- Where/when they cluster.
    local parts = {}
    if a.combatFrac >= 0.5 then parts[#parts + 1] = L.ADVISE_PAT_COMBAT end
    if a.movingFrac >= 0.5 then parts[#parts + 1] = L.ADVISE_PAT_TRAVEL end
    if a.topCtx then parts[#parts + 1] = L[ns.CONTEXT_LABEL[a.topCtx] or "CTX_WORLD"] end
    if a.topZone and a.zoneFrac >= 0.25 then parts[#parts + 1] = format(L.ADVISE_PAT_ZONE, a.topZone) end
    if #parts > 0 then add(format(L.ADVISE_WHERE, concat(parts, ", "))) end
    add("")

    -- What's causing them (cause breakdown, biggest first).
    if a.game > 0 then
        add(col(HEAD, L.ADVISE_CAUSE_HEADER))
        local arr = {}
        for k, n in pairs(DB.data.totals.causes) do arr[#arr + 1] = { k = k, n = n } end
        sort(arr, function(x, y) return x.n > y.n end)
        for i = 1, #arr do
            add(format(L.EXPORT_CAUSE_LINE, L[arr[i].k], arr[i].n))
        end
        add("")
    end

    -- What you can try.
    add(col(HEAD, L.ADVISE_TRY_HEADER))
    local cause = a.topCause or "HEADLINE_ENGINE"
    local tipKey = TIP[cause]
    if tipKey then add(L[tipKey]) end
    if a.raidDominant then add(col(MUTE, L.ADVISE_RAID_NOTE)) end

    local list = ADVICE[cause] or ADVICE.HEADLINE_ENGINE
    local suggested = false
    for i = 1, #list do
        local base = list[i]
        local meta = CVAR[base]
        if meta then
            local name, value, default = resolve(base, a.raidDominant)
            if name and isElevated(meta, value, default) then
                suggested = true
                if meta.kind == "toggle" then
                    add("- " .. format(L.ADVISE_TOGGLE, L[meta.labelKey]))
                else
                    add("- " .. format(L.ADVISE_SLIDER, L[meta.labelKey], pretty(value), pretty(default)))
                end
            end
        end
    end
    if not suggested then add(L.ADVISE_SETTINGS_OK) end
    add("")

    -- Your relevant settings (current vs default; elevated ones in amber).
    add(col(HEAD, L.ADVISE_SETTINGS_HEADER))
    for i = 1, #CVAR_ORDER do
        local base = CVAR_ORDER[i]
        local meta = CVAR[base]
        local name, value, default = resolve(base, a.raidDominant)
        if name and meta then
            local lineText = format(L.ADVISE_SETTING_LINE, L[meta.labelKey], pretty(value), pretty(default))
            if isElevated(meta, value, default) then
                add(col(COLOR[STATE.ELEVATED], lineText))
            else
                add(lineText)
            end
        end
    end
    add("")

    -- Where to change them.
    add(L.ADVISE_CHANGE_WHERE)
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("AdvancedInterfaceOptions") then
        add(L.ADVISE_AIO)
    end

    return concat(lines, "\n")
end
