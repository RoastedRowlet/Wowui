local ADDON, ns = ...
local L      = ns.L
local format = string.format
local floor  = math.floor

-- Our own folder name, used to keep StutterAlert out of its own blame list.
ns.ADDON = ADDON

-- Profiler metric enum fields. See DESIGN-NOTES.md: Profiler on every client.
local M = Enum.AddOnProfilerMetric
ns.METRIC = {
    LastTime             = M.LastTime,             -- ms spent by the addon in the most recent tick
    RecentAverageTime    = M.RecentAverageTime,    -- avg over last 60 ticks
    SessionAverageTime   = M.SessionAverageTime,   -- avg since login: the chronic, always-on cost
    EncounterAverageTime = M.EncounterAverageTime, -- avg during the current encounter
    PeakTime             = M.PeakTime,
    CountTimeOver1Ms     = M.CountTimeOver1Ms,
    CountTimeOver5Ms     = M.CountTimeOver5Ms,
    CountTimeOver10Ms    = M.CountTimeOver10Ms,
    CountTimeOver50Ms    = M.CountTimeOver50Ms,
    CountTimeOver100Ms   = M.CountTimeOver100Ms,
    CountTimeOver500Ms   = M.CountTimeOver500Ms,
    CountTimeOver1000Ms  = M.CountTimeOver1000Ms,
}

-- Severity state machine levels.
ns.STATE = {
    CALM     = 1,
    ELEVATED = 2,
    CRITICAL = 3,
}

-- Colors per state (r, g, b). Calm is intentionally muted; the loud states
-- carry the meaning. ENGINE is a distinct hue so "not your addons" reads
-- differently from "an addon is spiking".
ns.COLOR = {
    [ns.STATE.CALM]     = { 0.35, 0.70, 0.40 }, -- soft green
    [ns.STATE.ELEVATED] = { 0.95, 0.65, 0.20 }, -- amber
    [ns.STATE.CRITICAL] = { 0.90, 0.25, 0.25 }, -- red
    ENGINE              = { 0.40, 0.55, 0.90 }, -- blue-ish: not addons
    -- Grey while monitoring is suspended by a frame cap. It must read as "off":
    -- green would claim everything was measured and fine.
    THROTTLED           = { 0.45, 0.45, 0.48 },
}

-- Inline attribution glyphs (FileDataIDs). Locale-independent, so they live here
-- rather than in the string table. WoW mark = a game/engine cause; addon mark =
-- a named addon culprit. ":0" auto-scales the icon to the surrounding text height.
ns.GLYPH_GAME  = "|T939375:0|t"

-- Generic marker for an addon that declares no icon of its own. The question
-- mark texture is the game's canonical "no icon" placeholder, so it always exists.
ns.GLYPH_ADDON_FALLBACK = "|TInterface\\ICONS\\INV_Misc_QuestionMark:0|t"

-- An addon's own icon as inline markup: IconTexture, then IconAtlas, then the
-- generic marker. A missing or invalid declaration falls through.
function ns.ResolveAddonIcon(name)
    local tex = C_AddOns.GetAddOnMetadata(name, "IconTexture")
    if tex and tex ~= "" then
        return "|T" .. tex .. ":0|t"
    end
    local atlas = C_AddOns.GetAddOnMetadata(name, "IconAtlas")
    if atlas and atlas ~= "" and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
        and type(CreateAtlasMarkup) == "function" then
        local markup = CreateAtlasMarkup(atlas, 14, 14)
        if markup and markup ~= "" then return markup end
    end
    return ns.GLYPH_ADDON_FALLBACK
end

-- Cached per-addon icon markup. Icons don't change at runtime, so resolve once.
ns.addonIcon = ns.addonIcon or {}
function ns.AddonGlyph(name)
    if not name then return ns.GLYPH_ADDON_FALLBACK end
    local cached = ns.addonIcon[name]
    if cached == nil then
        cached = ns.ResolveAddonIcon(name)
        ns.addonIcon[name] = cached
    end
    return cached
end

-- Strip embedded color codes (|cAARRGGBB ... |r) from a string, so addon titles
-- that color themselves render in one neutral color wherever we show them.
function ns.StripColor(s)
    if type(s) ~= "string" then return s end
    s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
    s = s:gsub("|r", "")
    return s
end

-- Per-addon version string, cached. Reported verbatim, never parsed or compared.
-- See DESIGN-NOTES.md: Version strings.
ns.addonVersion = ns.addonVersion or {}
function ns.AddonVersion(name)
    if not name then return nil end
    local cached = ns.addonVersion[name]
    if cached == nil then
        local ok, v = pcall(C_AddOns.GetAddOnMetadata, name, "Version")
        -- `false` marks "asked, none declared", so we never re-query.
        cached = (ok and type(v) == "string" and v ~= "") and ns.StripColor(v) or false
        ns.addonVersion[name] = cached
    end
    if cached == false then return nil end
    return cached
end

-- Allocation buckets for hitch signatures. See DESIGN-NOTES.md: Allocation buckets.
ns.ALLOC_BUCKET = {
    NONE   = "ALLOC_NONE",
    SMALL  = "ALLOC_SMALL",
    MEDIUM = "ALLOC_MEDIUM",
    LARGE  = "ALLOC_LARGE",
}

function ns.AllocBucket(kb)
    if not kb or kb <= 16 then return ns.ALLOC_BUCKET.NONE end
    if kb < 256   then return ns.ALLOC_BUCKET.SMALL end
    if kb < 2048  then return ns.ALLOC_BUCKET.MEDIUM end
    return ns.ALLOC_BUCKET.LARGE
end

-- ---------------------------------------------------------------------------
-- Library packages, matched by name. A match only adds a caveat to the report,
-- never moves blame. See DESIGN-NOTES.md: Library packages.
-- ---------------------------------------------------------------------------
local LIB_PATTERNS = {
    "_Libraries$", "_Libs$", "_Lib$",
    "^!?[Ll]ib[A-Z]", "^LibStub$", "^CallbackHandler",
    "^Ace%d", "[Ll]ibraries$",
}

function ns.IsLibraryPackage(name)
    if type(name) ~= "string" then return false end
    for i = 1, #LIB_PATTERNS do
        if name:find(LIB_PATTERNS[i]) then return true end
    end
    return false
end

-- "ElvUI_Libraries" -> "ElvUI", but only when that addon is actually loaded, so
-- we never invent a host that is not there.
function ns.LibraryHostOf(name)
    if type(name) ~= "string" then return nil end
    local base = name:match("^(.-)_[Ll]ib")
    if base and base ~= "" and ns.addonTitle and ns.addonTitle[base] then
        return ns.addonTitle[base]
    end
    return nil
end

-- Seconds -> a short readable duration. Returns nil below one second so callers
-- can omit the line entirely rather than print "0s".
function ns.FormatDuration(sec)
    if type(sec) ~= "number" or sec < 1 then return nil end
    local whole = floor(sec)
    local h = floor(whole / 3600)
    local m = floor((whole % 3600) / 60)
    if h > 0 then return format(L.DUR_HM, h, m) end
    if m > 0 then return format(L.DUR_M, m) end
    return format(L.DUR_S, whole)
end

-- Kilobytes -> a readable size, switching to MB once that reads better.
function ns.FormatKB(kb)
    if type(kb) ~= "number" then return nil end
    if kb >= 1024 then
        return format(L.UNIT_MB, kb / 1024)
    end
    return format(L.UNIT_KB, floor(kb + 0.5))
end

-- Context bucket keys to locale keys. Only retail's five-man label names
-- Mythic+, which no Classic client has.
ns.CONTEXT_LABEL = {
    raid     = "CTX_RAID",
    dungeon  = ns.IsRetail and "CTX_DUNGEON" or "CTX_DUNGEON_PLAIN",
    pvp      = "CTX_PVP",
    city     = "CTX_CITY",
    world    = "CTX_WORLD",
    scenario = "CTX_SCENARIO",
}

-- Severity level -> locale key.
ns.SEVERITY_LABEL = {
    [ns.STATE.CALM]     = "SEV_CALM",
    [ns.STATE.ELEVATED] = "SEV_ELEVATED",
    [ns.STATE.CRITICAL] = "SEV_CRITICAL",
}

-- Frame-cap console variable to the locale key of its options-menu name.
ns.CAP_CVAR_LABEL = {
    maxFPSBk = "CVAR_MAX_FPS_BK",
    maxFPS   = "CVAR_MAX_FPS",
}

-- Readable name for a cap console variable. Falls back to the raw name only if
-- an unmapped variable ever reaches here, which is better than showing nothing.
function ns.CapCVarLabel(name)
    if type(name) ~= "string" then return nil end
    local key = ns.CAP_CVAR_LABEL[name]
    return key and L[key] or name
end
