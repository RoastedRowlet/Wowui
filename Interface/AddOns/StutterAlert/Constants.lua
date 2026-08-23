local ADDON, ns = ...
local L      = ns.L
local format = string.format
local floor  = math.floor

-- Our own folder name, used to keep StutterAlert out of its own blame list.
ns.ADDON = ADDON

-- Cache the profiler metric enum fields we use. All twelve of these were
-- verified present on 12.0.7 (build 68887) by dumping Enum.AddOnProfilerMetric.
--
-- The CountTimeOver* ladder is effectively a per-addon cost histogram the client
-- maintains for free, so we never have to sample frame times ourselves to learn
-- how an addon normally behaves.
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
}

-- Inline attribution glyphs (FileDataIDs). Locale-independent, so they live here
-- rather than in the string table. WoW mark = a game/engine cause; addon mark =
-- a named addon culprit. ":0" auto-scales the icon to the surrounding text height.
ns.GLYPH_GAME  = "|T939375:0|t"

-- Generic marker for an addon that declares no icon of its own. The question
-- mark texture is the game's canonical "no icon" placeholder, so it always exists.
ns.GLYPH_ADDON_FALLBACK = "|TInterface\\ICONS\\INV_Misc_QuestionMark:0|t"

-- Resolve an addon's own icon to an inline markup string. Prefers a declared
-- IconTexture (path or FileDataID), then an IconAtlas, then the generic marker.
-- Every branch is guarded so a missing/invalid declaration can't error or render
-- a broken square -- it just falls through to the next option.
function ns.ResolveAddonIcon(name)
    local tex = C_AddOns.GetAddOnMetadata(name, "IconTexture")
    if tex and tex ~= "" then
        return "|T" .. tex .. ":0|t"
    end
    local atlas = C_AddOns.GetAddOnMetadata(name, "IconAtlas")
    if atlas and atlas ~= "" and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
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

-- Cached per-addon version string, resolved once. Reported VERBATIM and never
-- parsed or compared: authors version however they like, and a live 12.0.7
-- install shows "330", "v12.0.20", "2.1.10" and "12.0.7 (v202607162050)" side by
-- side, so any comparison logic would be guesswork.
--
-- Note there is no way to read an addon's "## Interface:" line: 12.0.7's
-- GetAddOnMetadata returns nil for it on every addon, so staleness can only ever
-- be judged by a human reading the version string.
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

-- Allocation buckets for hitch signatures. A long frame that allocated megabytes
-- was computing (building tables, concatenating, serializing); one that
-- allocated almost nothing was blocking on the engine (asset loads, cache
-- misses, tooltip scans). That single distinction separates the two fundamental
-- kinds of addon hitch, so it earns a place in the signature.
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
-- Library / support packages.
--
-- When one of these is named as a culprit the profiler is not wrong, but it is
-- naming something no author can act on. 12.0.7 bills whichever addon owns the
-- executing code, and a shared library frame belongs to whichever copy won
-- LibStub. Verified directly with a probe: calling into another addon's function
-- does NOT re-attribute the cost, so every consumer of a shared library frame
-- has its time billed to the library's owner.
--
-- Detection is by name and is therefore a heuristic. It only ever ADDS a caveat
-- to the report - it never suppresses or moves blame - so a false positive costs
-- one hedged sentence rather than a wrong accusation.
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

-- Context bucket keys -> locale keys, used for both display and aggregates.
ns.CONTEXT_LABEL = {
    raid     = "CTX_RAID",
    dungeon  = "CTX_DUNGEON",
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
