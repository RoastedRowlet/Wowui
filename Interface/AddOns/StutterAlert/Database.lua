local _, ns = ...

local DB = {}
ns.DB = DB

-- Last few combat pulls, kept IN MEMORY ONLY (never written to SavedVariables),
-- so the tooltip can show recent outcomes for review without persisting them.
-- Newest first; trimmed to MAX_SESSION_PULLS.
local sessionPulls = {}
local MAX_SESSION_PULLS = 5

-- Canonical empty lifetime-tally structure. Defined once and reused for fresh
-- installs, history clears, and version resets so the shape never drifts.
-- gameCtx records WHERE/WHEN non-addon hitches happen, for the advice panel.
local function freshTotals()
    return {
        all = 0, addon = 0, game = 0,
        -- Seconds actually monitored (loading screens excluded). Without this a
        -- hitch count is uninterpretable: 454 hitches is alarming across twenty
        -- minutes and unremarkable across twenty hours.
        monitoredSec = 0,
        causes  = {},
        gameCtx = { combat = 0, moving = 0, byCtx = {}, byZone = {} },
    }
end

-- How many inter-hitch gaps to keep per addon. Enough to recognise a rhythm,
-- few enough that a busy session cannot bloat SavedVariables.
local MAX_GAPS = 12

-- Canonical per-addon aggregate. Defined once so that entries created by a
-- hitch and entries created by a memory sample always have the same shape.
local function newAggregate()
    return {
        hitches  = 0,
        sumMs    = 0,
        peakMs   = 0,
        peakTime = nil,
        peakMult = nil,
        ctx      = {},   -- [ctxKey] = count
        gaps     = {},   -- recent seconds between this addon's hitches
        coWith   = {},   -- [otherAddon] = times it spiked in the same cluster
        sigs     = {},   -- [signature] = { n, peakMs }
        events     = {}, -- [eventName] = how many of its hitches that event fired on
        eventFires = {}, -- [eventName] = total times it fired across those hitches
        prefixes   = {}, -- [addonMessagePrefix] = how many of its hitches carried it
    }
end

-- All of this is account-bound: the TOC declares only `## SavedVariables`
-- (no PerCharacter), so this single table follows the player across every
-- character on the WoW account.
ns.DEFAULTS = {
    version = 4,

    settings = {
        enabled            = true,

        -- Overlay position. usingDefaultAnchor = true means "pinned below the
        -- minimap"; once the player drags it, we store an absolute position
        -- relative to UIParent and flip this to false.
        usingDefaultAnchor = true,
        point              = "TOP",
        relativePoint      = "BOTTOM",
        x                  = 0,
        y                  = -6,
        locked             = true,
        buttonSize         = 32,
        bannerGrowthOverride = "AUTO",

        -- Toast banners: how long each stays before fading, and how many can
        -- stack at once. Summaries linger longer than live hitch banners.
        bannerHoldSec      = 10,
        summaryHoldSec     = 14,
        bannerStackMax     = 4,

        -- Detection thresholds (milliseconds of frame time).
        hitchThresholdMs   = 50,   -- a frame this long counts as a felt hitch
        criticalFrameMs    = 100,  -- single-frame "this one really hurt" mark

        -- Severity score (leaky bucket). A hitch adds (frameMs-threshold)*gain;
        -- the score decays by decayPerSec each second of calm.
        severityGain       = 0.02,
        severityDecayPerSec= 1.5,
        elevatedAt         = 0.8,
        criticalAt         = 2.0,
        minDwellSec        = 1.2,  -- hold a loud state at least this long (anti-flicker)
        headlineLatchSec   = 1.0,  -- hold the named culprit at least this long to be readable

        -- Attribution. If addon-attributed ms is below this fraction of the
        -- frame time, we call it engine/server rather than blaming an addon.
        addonBlameFraction = 0.5,
        topK               = 3,

        -- Quality-of-life.
        zoneGraceSec       = 3,    -- ignore hitches right after a loading screen
        soundOnCritical    = false,
        muted              = {},   -- [addonName] = true

        -- Storage caps.
        maxLogEntries      = 100,
    },

    -- Lifetime tallies (since history was last cleared), kept in sync with the
    -- log/aggregates but NEVER trimmed, so the export report's figures reconcile
    -- against one another instead of mixing a capped window with all-time data.
    totals = freshTotals(),

    -- Rolling per-addon aggregates: [addonName] = {...}
    -- An entry here means the addon has actually been blamed for a hitch.
    aggregates = {},

    -- Per-addon memory snapshots: [addonName] = { kb, delta, peak }.
    -- Kept separate from aggregates because this is sampled for EVERY loaded
    -- addon, and folding it into aggregates would create a full hitch record
    -- (with its empty ctx/gaps/coWith/sigs tables) for a hundred innocent addons.
    memory = {},

    -- Capped hitch log (newest at the end).
    log = {},
}

local function deepCopy(src)
    if type(src) ~= "table" then return src end
    local t = {}
    for k, v in pairs(src) do t[k] = deepCopy(v) end
    return t
end

-- Fill in any keys missing from saved data (handles upgrades cleanly).
local function applyDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then target[k] = {} end
            applyDefaults(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
end

function DB:Init()
    if type(StutterAlertDB) ~= "table" then
        StutterAlertDB = deepCopy(ns.DEFAULTS)
    else
        applyDefaults(StutterAlertDB, ns.DEFAULTS)
        -- Reset stored history when the schema changed so every figure starts from
        -- the same point: v2 introduced reconciled `totals`, v3 added the per-cause
        -- context tally (gameCtx), v4 added per-addon versions, allocation, frame
        -- share, signatures, gaps and memory. Without a reset, old counts and the
        -- new tallies would describe different spans, and old aggregates would be
        -- missing sub-tables the report now expects.
        -- (Diagnostic data only; nothing of value lost.)
        if (StutterAlertDB.version or 1) < 4 then
            StutterAlertDB.log = {}
            StutterAlertDB.aggregates = {}
            StutterAlertDB.memory = {}
            StutterAlertDB.totals = freshTotals()
            StutterAlertDB.version = 4
        end
    end
    self.data = StutterAlertDB
    self.settings = StutterAlertDB.settings
end

-- Record one hitch. `record` is the structured event built by the Detector.
function DB:RecordHitch(record)
    local data = self.data
    local s = self.settings

    -- Ring buffer: append, trim from the front past the cap.
    local log = data.log
    log[#log + 1] = record
    while #log > s.maxLogEntries do
        table.remove(log, 1)
    end

    -- Lifetime tallies: every hitch counts here regardless of the log cap, so the
    -- export report's TL;DR and per-cause counts share one window with Top Sources.
    local t = data.totals
    t.all = t.all + 1
    if record.isAddon then
        t.addon = t.addon + 1
    else
        t.game = t.game + 1
        local ck = record.causeKey or "HEADLINE_ENGINE"
        t.causes[ck] = (t.causes[ck] or 0) + 1

        -- Where/when this non-addon hitch happened (powers the advice panel).
        local gctx = t.gameCtx
        local rctx = record.ctx
        if rctx then
            if rctx.inCombat then gctx.combat = gctx.combat + 1 end
            if rctx.moving   then gctx.moving = gctx.moving + 1 end
            if rctx.zone     then gctx.byZone[rctx.zone] = (gctx.byZone[rctx.zone] or 0) + 1 end
        end
        local cb = record.ctxKey or "world"
        gctx.byCtx[cb] = (gctx.byCtx[cb] or 0) + 1
    end

    -- Aggregates only make sense when an addon was actually blamed.
    if record.isAddon and record.culprit then
        local agg = data.aggregates[record.culprit]
        if not agg then
            agg = newAggregate()
            data.aggregates[record.culprit] = agg
        end
        agg.hitches = agg.hitches + 1
        agg.sumMs   = agg.sumMs + record.culpritMs

        -- Version seen at hitch time. Keeping first and last makes it obvious
        -- when a report spans an update, so an author reading it knows whether
        -- these hitches predate a fix they already shipped.
        if record.culpritVer then
            agg.firstVer = agg.firstVer or record.culpritVer
            agg.lastVer  = record.culpritVer
        end

        if record.culpritShare then
            agg.sumShare = (agg.sumShare or 0) + record.culpritShare
            if record.culpritShare > (agg.peakShare or 0) then
                agg.peakShare = record.culpritShare
            end
        end

        local alloc = record.allocKB or 0
        if alloc > 0 then
            agg.sumAlloc = (agg.sumAlloc or 0) + alloc
            if alloc > (agg.peakAlloc or 0) then agg.peakAlloc = alloc end
        end

        -- Track the exact time (and how abnormal) the worst spike was
        if record.culpritMs > agg.peakMs then
            agg.peakMs      = record.culpritMs
            agg.peakTime    = record.t
            agg.peakMult    = record.culpritMult
            agg.peakVer     = record.culpritVer
            agg.peakOver    = record.culpritOver
            agg.peakAllocAt = alloc
            agg.peakEv      = record.ev
        end

        local bucket = record.ctxKey or "world"
        agg.ctx[bucket] = (agg.ctx[bucket] or 0) + 1

        -- Rhythm. Evenly spaced hitches point at a ticker; ragged ones point at
        -- something event-driven. That distinction is inferred from timing alone.
        if record.gap and record.gap > 0 then
            local g = agg.gaps
            g[#g + 1] = record.gap
            while #g > MAX_GAPS do table.remove(g, 1) end
        end

        if record.coWith then
            agg.coWith[record.coWith] = (agg.coWith[record.coWith] or 0) + 1
        end

        -- Event tallies count HITCHES an event was present on, not raw fire
        -- counts. "Fired on 4 of this addon's 5 hitches" is evidence of a
        -- trigger; "fired 300 times" is mostly evidence that the game is busy.
        if record.ev then
            local list = record.ev.list
            if list then
                for i = 1, #list do
                    local name = list[i].name
                    agg.events[name] = (agg.events[name] or 0) + 1
                    -- Raw fire count as well, so a tie on presence can be broken
                    -- by which event was actually hammering the frame.
                    agg.eventFires[name] = (agg.eventFires[name] or 0) + (list[i].n or 1)
                end
            end
            if record.ev.prefixes then
                for prefix in pairs(record.ev.prefixes) do
                    agg.prefixes[prefix] = (agg.prefixes[prefix] or 0) + 1
                end
            end
        end

        if record.sigKey then
            local sig = agg.sigs[record.sigKey]
            if not sig then
                sig = { n = 0, peakMs = 0 }
                agg.sigs[record.sigKey] = sig
            end
            sig.n = sig.n + 1
            if record.culpritMs > sig.peakMs then sig.peakMs = record.culpritMs end
        end
    end
end

-- Record a memory sample for one addon. Called only from the loading-screen
-- sampler, and deliberately for EVERY loaded addon rather than only ones that
-- have hitched, so growth is visible before it ever causes a stutter.
function DB:RecordMemory(name, kb)
    local mem = self.data.memory[name]
    if not mem then
        mem = { kb = kb, peak = kb }
        self.data.memory[name] = mem
        return -- first sample: no delta to report yet
    end
    mem.delta = kb - mem.kb
    mem.kb    = kb
    if kb > (mem.peak or 0) then mem.peak = kb end
end

-- Current memory snapshot for one addon, or nil if never sampled.
function DB:GetMemory(name)
    return self.data.memory and self.data.memory[name]
end

-- Mean seconds between this addon's hitches, but only when they are regular
-- enough for the average to mean anything. A coefficient of variation above
-- 25% reads as random rather than periodic, and we return nil rather than
-- claim a rhythm that is not there.
function DB:GetPeriod(agg)
    local g = agg and agg.gaps
    if not g or #g < 3 then return nil end

    local sum = 0
    for i = 1, #g do sum = sum + g[i] end
    local mean = sum / #g
    if mean <= 0 then return nil end

    local varSum = 0
    for i = 1, #g do
        local d = g[i] - mean
        varSum = varSum + d * d
    end
    local sd = math.sqrt(varSum / #g)
    if (sd / mean) > 0.25 then return nil end

    return mean
end

-- The signature that accounts for most of an addon's hitches, if one does.
-- Returns the signature key and its count.
function DB:GetDominantSignature(agg)
    if not agg or not agg.sigs then return nil end
    local bestKey, bestN
    for key, sig in pairs(agg.sigs) do
        -- Ties broken by key, so a report generated twice reads the same twice.
        if not bestKey or sig.n > bestN or (sig.n == bestN and key < bestKey) then
            bestKey, bestN = key, sig.n
        end
    end
    if not bestKey or bestN < 2 then return nil end
    return bestKey, bestN
end

-- The event present on the most of this addon's hitches, when it is present on
-- enough of them to be worth naming. A trigger that shows up on half or fewer
-- is coincidence, not a lead.
function DB:GetDominantEvent(agg)
    if not agg or not agg.events or (agg.hitches or 0) < 2 then return nil end

    local fires = agg.eventFires or {}
    local bestName, bestN, bestFires
    for name, n in pairs(agg.events) do
        local f = fires[name] or 0
        local better
        if not bestName then
            better = true
        elseif n ~= bestN then
            better = n > bestN
        elseif f ~= bestFires then
            -- Same number of hitches: prefer the one that fired more often. Two
            -- events present on every hitch are not equally suspicious if one
            -- fired thirty times and the other once.
            better = f > bestFires
        else
            better = name < bestName -- final tie-break, so output never flaps
        end
        if better then bestName, bestN, bestFires = name, n, f end
    end

    if not bestName or bestN <= (agg.hitches / 2) then return nil end
    return bestName, bestN
end

-- Highest count in a [key] = count map, with ties broken by key so the report
-- says the same thing every time it is generated.
local function topOfMap(map)
    if not map then return nil end
    local bestKey, bestN
    for key, n in pairs(map) do
        if not bestKey or n > bestN or (n == bestN and key < bestKey) then
            bestKey, bestN = key, n
        end
    end
    return bestKey, bestN
end

-- The addon-message prefix seen on the most of this addon's hitches.
function DB:GetDominantPrefix(agg)
    return topOfMap(agg and agg.prefixes)
end

-- The addon this one most often spikes alongside, and how many times.
function DB:GetTopCoOccurrence(agg)
    return topOfMap(agg and agg.coWith)
end

-- Most recent `n` hitches, newest first.
function DB:GetRecentHitches(n)
    local log = self.data.log
    local out = {}
    for i = #log, math.max(1, #log - n + 1), -1 do
        out[#out + 1] = log[i]
    end
    return out
end

-- Top stutter sources this session, by hitch count then peak. Returns an
-- array of { name, hitches, peakMs }.
function DB:GetTopSources(n)
    local out = {}
    for name, agg in pairs(self.data.aggregates) do
        -- Memory sampling creates an aggregate for every loaded addon, so an
        -- entry existing does not mean it ever caused a stutter.
        if (agg.hitches or 0) > 0 then
            out[#out + 1] = {
                name = name, agg = agg,
                hitches = agg.hitches, peakMs = agg.peakMs, peakTime = agg.peakTime,
            }
        end
    end
    table.sort(out, function(a, b)
        if a.hitches ~= b.hitches then return a.hitches > b.hitches end
        return a.peakMs > b.peakMs
    end)
    for i = #out, n + 1, -1 do out[i] = nil end
    return out
end

-- Summarize the stored log over a window. sinceTime == nil means the whole log.
-- Returns totals, the worst addon, the worst single frame of any cause, and a
-- per-cause count of the non-addon hitches (keyed by HEADLINE_* causeKey).
function DB:Summarize(sinceTime)
    local log = self.data.log
    local total, addonCount = 0, 0
    local worstMs, worstTitle, worstMult, worstCulprit = 0, nil, nil, nil
    local worstAnyMs = 0
    local causes = {}

    for i = #log, 1, -1 do
        local r = log[i]
        if sinceTime and r.t < sinceTime then break end
        total = total + 1
        if (r.ms or 0) > worstAnyMs then worstAnyMs = r.ms or 0 end

        if r.isAddon then
            addonCount = addonCount + 1
            if (r.culpritMs or 0) > worstMs then
                worstMs      = r.culpritMs or 0
                worstTitle   = r.culpritTitle or r.culprit
                worstCulprit = r.culprit
                worstMult    = r.culpritMult
            end
        else
            local key = r.causeKey or "HEADLINE_ENGINE"
            causes[key] = (causes[key] or 0) + 1
        end
    end

    return {
        total        = total,
        addonCount   = addonCount,
        worstMs      = worstMs,
        worstTitle   = worstTitle,
        worstCulprit = worstCulprit,
        worstMult    = worstMult,
        worstAnyMs   = worstAnyMs,
        causes       = causes,
    }
end

-- Lifetime totals (since last cleared) for the export report, so every figure
-- shares one window. The worst addon is read from the all-time aggregates.
function DB:GetTotals()
    local t = self.data.totals
    local worstTitle, worstMs, worstMult
    for name, agg in pairs(self.data.aggregates) do
        if (agg.peakMs or 0) > (worstMs or 0) then
            worstMs    = agg.peakMs
            worstTitle = ns.addonTitle[name] or name
            worstMult  = agg.peakMult
        end
    end
    return {
        total      = t.all,
        addonCount = t.addon,
        gameCount  = t.game,
        causes     = t.causes,
        worstTitle = worstTitle,
        worstMs    = worstMs or 0,
        worstMult  = worstMult,
    }
end

-- Push one completed pull into the in-memory, session-only ring (newest first).
function DB:RecordPull(pull)
    table.insert(sessionPulls, 1, pull)
    while #sessionPulls > MAX_SESSION_PULLS do
        table.remove(sessionPulls)
    end
end

-- The last few pulls this session (newest first). Read-only; never persisted.
function DB:GetRecentPulls()
    return sessionPulls
end

function DB:ClearHistory()
    self.data.log = {}
    self.data.aggregates = {}
    -- Memory goes too: its deltas are measured against the last sample, so
    -- keeping them across a clear would report growth from outside the window
    -- every other figure in the report now covers.
    self.data.memory = {}
    self.data.totals = freshTotals()
    wipe(sessionPulls)
end