local _, ns = ...
local L  = ns.L
local DB = ns.DB

local STATE  = ns.STATE
local METRIC = ns.METRIC

-- Hot-path locals.
local GetTime           = GetTime
local time              = time
local floor             = math.floor
local format            = string.format
local collectgarbage    = collectgarbage
local GetOverallMetric  = C_AddOnProfiler.GetOverallMetric
local GetAddOnMetric    = C_AddOnProfiler.GetAddOnMetric
local LastTime          = METRIC.LastTime

local Detector = {}
ns.Detector = Detector

-- Per-session state (file upvalues).
local severity        = 0
local state           = STATE.CALM
local stateEnteredAt  = 0
local graceUntil      = 0
local prevGC          = 0

-- Rolling "normal" frame time (EMA, ms) and a warm-up gate, used to tell an
-- isolated spike apart from a machine that is genuinely struggling.
local baselineMs       = 0
local baselineReady    = false
local monitorStartedAt = 0

-- Timestamps of recent hitches, pruned to CLUSTER_WINDOW_SEC (drives "sustained").
local hitchWindow      = {}

-- Dirty-tracking so we only touch the overlay when something visibly changes,
-- not every frame.
local lastPushedState    = nil

-- Cached list of addon names + friendly titles, refreshed on load events.
ns.addonList  = ns.addonList  or {}
ns.addonTitle = ns.addonTitle or {}

function Detector:RebuildAddonList()
    local list, titles = {}, {}
    local selfName = ns.ADDON
    local n = C_AddOns.GetNumAddOns()
    for i = 1, n do
        local name, title = C_AddOns.GetAddOnInfo(i)
        -- StutterAlert is deliberately absent from the blame list. Naming
        -- ourselves as a stutter source would be worse than useless, and our own
        -- constant cost is still reported honestly in the chronic-cost section.
        if name and name ~= selfName and C_AddOns.IsAddOnLoaded(i) then
            list[#list + 1] = name
            -- Strip any embedded color codes so names show in one neutral color
            -- everywhere (banner, tooltip, summary). Some addons color their titles.
            titles[name] = (title and title ~= "") and ns.StripColor(title) or name
            ns.AddonVersion(name) -- warm the version cache while we are here
        end
    end
    ns.addonList  = list
    ns.addonTitle = titles
end

-- ---------------------------------------------------------------------------
-- Chronic cost: what your addons spend on EVERY frame, hitch or no hitch.
--
-- SessionAverageTime is maintained by the client, so this is a read rather than
-- a measurement. Unlike everything else here it deliberately includes
-- StutterAlert itself: our own overhead is a real cost to the player and hiding
-- it would be dishonest, even though we never blame ourselves for a spike.
-- ---------------------------------------------------------------------------
function Detector:GetChronicCost(topN)
    local rows, sum = {}, 0
    local n = C_AddOns.GetNumAddOns()
    for i = 1, n do
        local name = C_AddOns.GetAddOnInfo(i)
        if name and C_AddOns.IsAddOnLoaded(i) then
            local avg = GetAddOnMetric(name, METRIC.SessionAverageTime)
            if type(avg) == "number" and avg > 0 then
                rows[#rows + 1] = { name = name, ms = avg }
                sum = sum + avg
            end
        end
    end
    table.sort(rows, function(a, b) return a.ms > b.ms end)
    for i = #rows, (topN or 5) + 1, -1 do rows[i] = nil end
    return rows, sum
end

-- ---------------------------------------------------------------------------
-- Per-addon memory, sampled ONLY inside the loading-screen grace window.
--
-- UpdateAddOnMemoryUsage was measured at 50-55 ms on a 107-addon install on
-- 12.0.7. That is three frames: calling it on a timer would make StutterAlert
-- the cause of a visible stutter every cycle, and calling it on a hitch frame
-- would make a bad frame worse. The one place it is free is behind a loading
-- screen, where a long frame is expected and already excluded from detection.
-- ---------------------------------------------------------------------------
local lastMemSample     = 0
local MEM_SAMPLE_GAP_SEC = 60

function Detector:SampleAddonMemory()
    if type(UpdateAddOnMemoryUsage) ~= "function" or type(GetAddOnMemoryUsage) ~= "function" then
        return
    end

    local now = GetTime()
    if lastMemSample > 0 and (now - lastMemSample) < MEM_SAMPLE_GAP_SEC then return end
    lastMemSample = now

    UpdateAddOnMemoryUsage()

    local list = ns.addonList
    for i = 1, #list do
        local name = list[i]
        local kb = GetAddOnMemoryUsage(name)
        if type(kb) == "number" and kb > 0 then
            DB:RecordMemory(name, kb)
        end
    end
end

-- Top-k addons by their LastTime this tick. Allocates a few small tables, but
-- this runs ONLY on a hitch frame (rare), never on calm frames.
local function getTopAddons(k)
    local list = ns.addonList
    local top = {}
    for i = 1, #list do
        local name = list[i]
        local ms = GetAddOnMetric(name, LastTime)
        if ms and ms > 0 then
            local pos = #top + 1
            for j = 1, #top do
                if ms > top[j].ms then pos = j break end
            end
            table.insert(top, pos, { name = name, ms = ms })
            top[k + 1] = nil
        end
    end
    return top
end

-- ---------------------------------------------------------------------------
-- Secret-value safety (12.0.7). Certain APIs return "secret" values in some
-- contexts (notably movement/position inside instanced combat). Insecure code
-- may not compare, do arithmetic on, serialize, or even evaluate the truthiness
-- of a secret -- any of those raises and taints execution. Our hitch records are
-- written to SavedVariables and rendered into the export report, so a secret
-- must NEVER reach ctx/records. These helpers read defensively: a hostile or
-- failing read degrades that one field to a safe default instead of aborting the
-- whole hitch, and only verified-plain values are returned.
local function toBool(v) return v and true or false end
local function plusZero(v) return v + 0 end

local function safeBool(thunk, default)
    local ok, v = pcall(thunk)
    if not ok then return default end
    local ok2, b = pcall(toBool, v) -- truthiness of a secret raises; catch it
    if ok2 then return b end
    return default
end

local function safeNum(thunk, default)
    local ok, v = pcall(thunk)
    if not ok or type(v) ~= "number" then return default end
    if not pcall(plusZero, v) then return default end -- arithmetic raises on a secret number
    return v
end

-- Movement is tracked from events rather than GetUnitSpeed (which returns a
-- secret number in 12.0.7). These events carry no secret payload; we just hold a
-- plain boolean. Always-on: cheap, and harmless while monitoring is disabled.
local isMoving = false
local moveWatcher = CreateFrame("Frame")
moveWatcher:RegisterEvent("PLAYER_STARTED_MOVING")
moveWatcher:RegisterEvent("PLAYER_STOPPED_MOVING")
moveWatcher:SetScript("OnEvent", function(_, event)
    isMoving = (event == "PLAYER_STARTED_MOVING")
end)

local function buildContext()
    local inCombat = safeBool(function() return UnitAffectingCombat("player") end, false)
    local resting  = safeBool(IsResting, false)
    local _, instanceType = IsInInstance()
    local key
    if instanceType == "raid" then
        key = "raid"
    elseif instanceType == "party" then
        key = "dungeon"
    elseif instanceType == "arena" or instanceType == "pvp" then
        key = "pvp"
    elseif instanceType == "scenario" then
        key = "scenario"
    elseif resting then
        key = "city"
    else
        key = "world"
    end

    -- Correlated conditions captured at hitch time (rare, so affordable). These
    -- are CONTEXT shown to help the player decide -- never asserted as the cause.
    -- Every read goes through the secret-safe helpers so a value that turns out
    -- secret in instanced combat degrades one field rather than killing the hitch.
    local nameplates = 0
    if C_NamePlate and C_NamePlate.GetNamePlates then
        local ok, plates = pcall(C_NamePlate.GetNamePlates)  -- 12.0.1: no args
        if ok and plates then nameplates = #plates end
    end

    local latencyWorld = safeNum(function()
        local _, _, _, lw = GetNetStats()
        return lw
    end, 0)

    local fps = floor(safeNum(GetFramerate, 0) + 0.5)
    local groupSize = safeNum(GetNumGroupMembers, 0)

    -- Map id + readable zone name (drives the advice panel's "mostly in <zone>").
    local mapID = safeNum(function() return C_Map and C_Map.GetBestMapForUnit("player") end, nil)
    local zoneName
    if mapID and C_Map and C_Map.GetMapInfo then
        local ok, mi = pcall(C_Map.GetMapInfo, mapID)
        if ok and mi and type(mi.name) == "string" then zoneName = mi.name end
    end

    local ctx = {
        inCombat     = inCombat,
        instanceType = instanceType,
        groupSize    = groupSize,
        mapID        = mapID,
        zone         = zoneName,
        nameplates   = nameplates,
        latencyWorld = latencyWorld,
        fps          = fps,
        moving       = isMoving,
        flying       = safeBool(IsFlying, false),
        mounted      = safeBool(IsMounted, false),
    }
    return ctx, key
end

-- Localized, context-aware label for a stored hitch record.
function ns.ContextLabelFor(rec)
    local key = (rec and rec.ctxKey) or "world"
    local label = L[ns.CONTEXT_LABEL[key] or "CTX_WORLD"]
    if rec and rec.ctx and rec.ctx.inCombat then
        label = label .. " " .. L.CTX_COMBAT_SUFFIX
    end
    return label
end

function Detector:GetSeverityLabel()
    return L[ns.SEVERITY_LABEL[state] or "SEV_CALM"]
end

-- ---------------------------------------------------------------------------
-- Non-addon cause classifier. When a hitch is not blamed on an addon, this
-- returns the locale KEY for the most likely cause, checked most-confident
-- first, ending in an honest engine/render remainder. This is inference from
-- correlated signals -- not ground truth -- so the labels stay hedged.
-- ---------------------------------------------------------------------------
-- Locked detection tuning (the shared benchmark; NOT user-configurable, so every
-- install measures the same way and reports stay comparable across machines).
local LOADING_TAIL_SEC   = 5     -- a hitch within this long after a zone-in = streaming
local BASELINE_TAU_SEC   = 1.5   -- EMA time-constant for "normal" frame time
local WARMUP_SEC         = 2     -- learn this machine before trusting hitch shape
local SMOOTH_FLOOR_MS    = 33    -- ~30 fps; baseline at/above this = the machine is struggling
local SPIKE_RATIO        = 3     -- frame must reach baseline*this (floored at hitchThresholdMs) to count
local CLUSTER_WINDOW_SEC = 5     -- look-back window for repeated hitches
local CLUSTER_COUNT      = 4     -- this many hitches in the window = sustained, even if baseline lags
local CLUSTER_COUNT      = 4     -- this many hitches in the window = sustained, even if baseline lags
local SCENE_UNITS        = 8     -- this many nearby units at hitch time = the engine is loading models/effects

-- ---------------------------------------------------------------------------
-- Non-addon cause classifier. Returns the locale KEY for the most likely cause,
-- most-confident first, ending in an honest engine/unclear remainder. This is
-- inference from correlated signals -- not ground truth -- so the labels stay
-- hedged. Network latency and raw FPS are deliberately NOT treated as causes:
-- latency does not make a single frame render long, and average FPS hides a
-- one-frame spike. Both are captured as context only (see buildContext).
-- ---------------------------------------------------------------------------
local function classifyNonAddon(gcThisFrame, ctx)
    -- 1. Asset streaming shortly after a loading screen / zone change.
    if GetTime() < (graceUntil + LOADING_TAIL_SEC) then
        return "HEADLINE_LOADING"
    end

    -- 2. Lua memory cleanup ran on this exact frame.
    if gcThisFrame then
        return "HEADLINE_GC"
    end

    -- 3. Until we've learned this machine's normal, don't characterize the shape.
    if not baselineReady then
        return "HEADLINE_UNCLEAR"
    end

    -- 4. Machine genuinely struggling: even ordinary frames are already slow.
    if baselineMs >= SMOOTH_FLOOR_MS then
        return "HEADLINE_SUSTAINED"
    end

    -- 5. Busy scene: many units nearby, so the engine is loading their models
    --    and effects this frame. Common on big pulls and crowded hubs.
    if ctx and ctx.nameplates and ctx.nameplates >= SCENE_UNITS then
        return "HEADLINE_SCENE"
    end

    -- 6. Sustained by clustering: a run of hitches even if the baseline lags.
    if #hitchWindow >= CLUSTER_COUNT then
        return "HEADLINE_SUSTAINED"
    end

    -- 7. In combat but not a big pull: spell visuals, particles, and projected
    --    effects loading this frame. Common on bosses and small packs.
    if ctx and ctx.inCombat then
        return "HEADLINE_COMBAT_FX"
    end

    -- 8. Travelling (especially flying/mounted): the engine is streaming terrain
    --    and textures as you move into new ground.
    if ctx and (ctx.flying or ctx.mounted or ctx.moving) then
        return "HEADLINE_STREAMING"
    end

    -- 9. Otherwise: an isolated engine spike (a one-off model/effect/asset load).
    return "HEADLINE_ENGINE"
end

-- ---------------------------------------------------------------------------
-- Event ring: what the game was dispatching on the frame that hitched.
--
-- Knowing WHICH addon was slow is only half an answer; this supplies what it was
-- reacting to. A frame with RegisterAllEvents receives every event, and we note
-- them per frame so a hitch can name its trigger.
--
-- Affordable because 12.0.7 does NOT deliver COMBAT_LOG_EVENT_UNFILTERED to a
-- RegisterAllEvents frame (verified on build 68887: zero dispatches across a ten
-- second window in the open world). Measured load was 35 dispatches/sec at
-- ~0.001 ms/frame, and that figure INCLUDED the profiling calls used to measure
-- it, so the real cost is lower still.
--
-- DOUBLE BUFFERED, and the direction matters. OnUpdate's `elapsed` describes the
-- frame that just ENDED, but that frame's successor has already dispatched its
-- events by the time OnUpdate runs. The events belonging to the hitch are
-- therefore always in the PREVIOUS bucket, never the current one. This was
-- verified rather than assumed: a controlled 300 ms burn showed the long
-- `elapsed` and the matching profiler reading land on the same frame. Reading
-- the wrong bucket would yield confident, plausible, wrong answers.
-- ---------------------------------------------------------------------------
local EVENT_CAP  = 128  -- per-frame slots; beyond this we only count the overflow
local EVENT_KEEP = 5    -- distinct events kept on a stored hitch record

local function newBucket()
    return { n = 0, over = 0, prefix = {} }
end

local evCur, evPrev = newBucket(), newBucket()

local eventWatcher = CreateFrame("Frame")

-- The hot path. One string compare, one integer increment, one array write, and
-- nothing else: no hashing, no table allocation, no counting. All aggregation
-- happens on hitch frames, which are rare.
local function onEventCapture(_, event, arg1)
    -- Verified not delivered on 12.0.7, but a single compare is cheap insurance
    -- against a future build changing that and flooding this handler.
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then return end

    local n = evCur.n + 1
    if n > EVENT_CAP then
        -- Overflow is itself a finding: something fired hundreds of times in one
        -- frame, which is usually the whole story.
        evCur.over = evCur.over + 1
        return
    end

    evCur.n = n
    evCur[n] = event

    -- The prefix names the addon whose comms these are, which is about as direct
    -- as attribution gets. Stored untouched: it is only ever inspected later,
    -- inside a pcall, because 12.0.7 can hand out secret values.
    if event == "CHAT_MSG_ADDON" then
        evCur.prefix[n] = arg1
    end
end

-- Stale prefix entries are deliberately NOT cleared on swap. A prefix at index i
-- is only ever read when the event at index i is CHAT_MSG_ADDON, and in that
-- case this frame overwrote it. Skipping the wipe keeps the per-frame cost to
-- two integer stores.
local function swapEventBuckets()
    local t = evPrev
    evPrev  = evCur
    evCur   = t
    evCur.n = 0
    evCur.over = 0
end

-- Summarize the frame that just ended. Runs ONLY on a hitch frame.
local function summarizeEvents()
    local b = evPrev

    -- An EMPTY summary rather than nil, because "nothing fired" is a real and
    -- useful finding: it means the work came from an OnUpdate or a timer rather
    -- than an event. Reserving nil for a genuine capture failure keeps the two
    -- cases distinguishable in the report.
    if b.n == 0 and b.over == 0 then
        return { list = {}, total = 0, over = 0 }
    end

    local counts, order = {}, {}
    for i = 1, b.n do
        local e = b[i]
        if counts[e] then
            counts[e] = counts[e] + 1
        else
            counts[e] = 1
            order[#order + 1] = e
        end
    end

    local list = {}
    for i = 1, #order do
        list[#list + 1] = { name = order[i], n = counts[order[i]] }
    end
    -- Ties broken by name, not left to table.sort. The first entry becomes part
    -- of the hitch signature, so an arbitrary winner would fragment signatures
    -- that are actually the same recurring fault.
    table.sort(list, function(x, y)
        if x.n ~= y.n then return x.n > y.n end
        return x.name < y.name
    end)
    for i = #list, EVENT_KEEP + 1, -1 do list[i] = nil end

    local prefixes
    for i = 1, b.n do
        if b[i] == "CHAT_MSG_ADDON" then
            local p = b.prefix[i]
            if type(p) == "string" then
                prefixes = prefixes or {}
                prefixes[p] = (prefixes[p] or 0) + 1
            end
        end
    end

    return { list = list, total = b.n, over = b.over, prefixes = prefixes }
end

-- Per-addon timing of previous hitches, in memory only. Gaps are meaningful
-- within a session; persisting them would produce nonsense like an eight-hour
-- "interval" spanning a logout.
local lastHitchAt = {}

-- The most recently blamed addon, for co-occurrence. When several addons spike
-- inside one cluster window it usually means a single shared trigger rather
-- than several independent faults, and saying so is more accurate than
-- accusing all of them separately.
local lastBlamed, lastBlamedAt = nil, 0

function Detector:OnHitch(frameMs, gcThisFrame, allocKB)
    local s = DB.settings
    local now = GetTime()

    -- Cluster tracking: count hitches inside the recent window. A run of hitches
    -- means the machine is genuinely struggling even if the baseline lags behind.
    local w = hitchWindow
    w[#w + 1] = now
    local cutoff = now - CLUSTER_WINDOW_SEC
    while w[1] and w[1] < cutoff do
        table.remove(w, 1)
    end

    -- Leaky-bucket: a worse hitch raises severity more.
    severity = severity + (frameMs - s.hitchThresholdMs) * s.severityGain

    -- Attribute to addons.
    local addonMs = GetOverallMetric(LastTime) or 0
    local top = getTopAddons(s.topK)

    local culprit, culpritMs
    for i = 1, #top do
        if not s.muted[top[i].name] then
            culprit   = top[i].name
            culpritMs = top[i].ms
            break
        end
    end

    -- How abnormal was this culprit versus its OWN recent average? (>1 means a
    -- spike above its normal cost, not just a consistently-heavy addon.)
    local culpritMult
    if culprit then
        local avg = GetAddOnMetric(culprit, METRIC.RecentAverageTime)
        if avg and avg > 0.01 and culpritMs then
            culpritMult = culpritMs / avg
        end
    end

    -- How much of the long frame was actually this addon? The blame gate below
    -- tests TOTAL addon time, so without this a frame where five addons each
    -- spent a moderate amount could be pinned wholly on one of them. Recording
    -- the share keeps the report honest about how strong the evidence is.
    local culpritShare
    if culpritMs and frameMs > 0 then
        culpritShare = culpritMs / frameMs
    end

    -- Build context first so the cause classifier can read the live scene.
    local ctx, ctxKey = buildContext()

    -- Blame an addon only if addon time accounts for a meaningful share of the
    -- spike; otherwise classify which non-addon cause is most likely.
    local isAddon  = (culprit ~= nil) and (addonMs >= frameMs * s.addonBlameFraction)
    local causeKey = (not isAddon) and classifyNonAddon(gcThisFrame, ctx) or nil

    -- What the game was dispatching on the frame that hitched. Captured for
    -- every hitch, addon or not, because "Busy scene" is far more useful when it
    -- can also say what was firing. Guarded: event payloads can be secret in
    -- 12.0.7, and losing the event list is preferable to losing the hitch.
    local okEv, events = pcall(summarizeEvents)
    if not okEv then events = nil end

    -- Everything below is captured only when an addon is actually blamed, so a
    -- game-caused hitch stays as cheap to record as it was before.
    local culpritVer, culpritSession, culpritOver, gap, coWith, sigKey
    if isAddon and culprit then
        culpritVer     = ns.AddonVersion(culprit)
        culpritSession = GetAddOnMetric(culprit, METRIC.SessionAverageTime)

        -- The client's own cost histogram for this addon. Cumulative for the
        -- session, so it answers "is this habitual or a one-off?" for free.
        culpritOver = {
            GetAddOnMetric(culprit, METRIC.CountTimeOver50Ms)   or 0,
            GetAddOnMetric(culprit, METRIC.CountTimeOver100Ms)  or 0,
            GetAddOnMetric(culprit, METRIC.CountTimeOver500Ms)  or 0,
            GetAddOnMetric(culprit, METRIC.CountTimeOver1000Ms) or 0,
        }

        local prev = lastHitchAt[culprit]
        if prev then gap = now - prev end
        lastHitchAt[culprit] = now

        if lastBlamed and lastBlamed ~= culprit and (now - lastBlamedAt) <= CLUSTER_WINDOW_SEC then
            coWith = lastBlamed
        end
        lastBlamed, lastBlamedAt = culprit, now

        -- Signature: repeated hitches that share one of these collapse into a
        -- single reported pattern instead of N identical-looking lines. The
        -- dominant event is part of it, so "always CHAT_MSG_ADDON in a dungeon"
        -- reads as one bug. If the event varies each time the signature will
        -- fragment, and that fragmentation is itself the finding: these are not
        -- the same fault repeating.
        local topEvent = events and events.list and events.list[1] and events.list[1].name
        sigKey = ctxKey
            .. "/" .. (ctx.inCombat and "combat" or "calm")
            .. "/" .. ns.AllocBucket(allocKB)
            .. "/" .. (topEvent or "-")
    end

    local rec = {
        t              = time(),
        ms             = floor(frameMs + 0.5),
        addonMs        = floor(addonMs + 0.5),
        allocKB        = floor((allocKB or 0) + 0.5),
        culprit        = culprit,
        culpritTitle   = culprit and (ns.addonTitle[culprit] or culprit) or nil,
        culpritMs      = culpritMs and floor(culpritMs + 0.5) or 0,
        culpritMult    = culpritMult,
        culpritShare   = culpritShare,
        culpritVer     = culpritVer,
        culpritSession = culpritSession,
        culpritOver    = culpritOver,
        gap            = gap,
        coWith         = coWith,
        sigKey         = sigKey,
        ev             = events,
        suspects       = top,
        isAddon        = isAddon,
        isGC           = gcThisFrame and true or false,
        causeKey       = causeKey,
        ctx            = ctx,
        ctxKey         = ctxKey,
    }
    DB:RecordHitch(rec)

    -- Surface this hitch as a toast banner. Repeated spikes from the same source
    -- coalesce into one banner (with an xN counter) that lives as long as the
    -- spikes keep coming, instead of stacking a fresh banner every frame.
    local toastKey, toastName, toastMs
    if isAddon then
        toastKey  = culprit
        toastName = rec.culpritTitle or culprit
        toastMs   = rec.culpritMs
    else
        toastKey  = causeKey or "HEADLINE_ENGINE"
        toastName = L[toastKey]
        toastMs   = rec.ms
    end
    ns.Overlay:PushToast(toastKey, toastName, isAddon, toastMs)

    if s.soundOnCritical and frameMs >= s.criticalFrameMs then
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON, "Master")
    end
end

local function updateState(s)
    local newState
    if severity >= s.criticalAt then
        newState = STATE.CRITICAL
    elseif severity >= s.elevatedAt then
        newState = STATE.ELEVATED
    else
        newState = STATE.CALM
    end

    -- Don't drop to a quieter state before the minimum dwell time (anti-flicker).
    if newState < state and (GetTime() - stateEnteredAt) < s.minDwellSec then
        newState = state
    end

    if newState ~= state then
        state = newState
        stateEnteredAt = GetTime()
    end
end

local function onUpdate(_, elapsed)
    local s = DB.settings
    local now = GetTime()
    local frameMs = elapsed * 1000

    -- Decay the severity bucket during calm.
    if severity > 0 then
        severity = severity - s.severityDecayPerSec * elapsed
        if severity < 0 then severity = 0 end
    end

    -- GC sawtooth: a drop in total Lua memory means a collection ran this frame.
    -- The same two reads also give us how much Lua memory the frame ALLOCATED,
    -- which costs nothing extra and is one of the strongest "why" signals we
    -- have: a long frame that allocated megabytes was computing, while one that
    -- allocated nothing was blocking on the engine.
    local curGC = collectgarbage("count")
    local allocKB = curGC - prevGC
    local gcThisFrame = curGC < (prevGC - 1)
    prevGC = curGC

    -- Effective hitch threshold: a real spike against THIS machine's normal,
    -- never below the absolute floor. The rule is identical for every install
    -- (the benchmark is the method, not the resulting millisecond value).
    local threshold = s.hitchThresholdMs
    if baselineReady then
        local rel = baselineMs * SPIKE_RATIO
        if rel > threshold then threshold = rel end
    end

    local inGrace = now < graceUntil

    -- Accumulate monitored time so the report can turn a raw hitch count into a
    -- rate. Loading screens are excluded, matching what detection ignores.
    if not inGrace then
        local totals = DB.data and DB.data.totals
        if totals then
            totals.monitoredSec = (totals.monitoredSec or 0) + elapsed
        end
    end

    if frameMs >= threshold and not inGrace then
        Detector:OnHitch(frameMs, gcThisFrame, allocKB)
    elseif not inGrace then
        -- Update the rolling baseline ONLY on non-hitch, non-loading frames, so a
        -- single spike or a loading screen can't poison the idea of "normal".
        local alpha = elapsed / BASELINE_TAU_SEC
        if alpha > 1 then alpha = 1 end
        if baselineMs <= 0 then
            baselineMs = frameMs
        else
            baselineMs = baselineMs + (frameMs - baselineMs) * alpha
        end
        if not baselineReady and (now - monitorStartedAt) >= WARMUP_SEC then
            baselineReady = true
        end
    end

    updateState(s)

    -- Event-driven UI: only re-tint the button when the severity state changes.
    -- Toast banners are pushed independently from OnHitch as hitches occur.
    if state ~= lastPushedState then
        lastPushedState = state
        ns.Overlay:Refresh(state)
    end

    -- Unconditionally last: every frame must advance the ring, including hitch
    -- frames and frames inside the loading grace. Skipping a swap on any path
    -- would slide the buffers out of step with the frame they describe.
    swapEventBuckets()
end

function Detector:Enable()
    if not self.frame then
        self.frame = CreateFrame("Frame")
    end
    prevGC = collectgarbage("count")

    -- Cold start: re-learn this machine's normal before judging hitch shape.
    baselineMs       = 0
    baselineReady    = false
    monitorStartedAt = GetTime()
    hitchWindow      = {}

    -- Start the event ring from empty so the first frames after enabling cannot
    -- attribute a hitch to events captured before monitoring began.
    evCur.n, evCur.over   = 0, 0
    evPrev.n, evPrev.over = 0, 0
    eventWatcher:SetScript("OnEvent", onEventCapture)
    eventWatcher:RegisterAllEvents()

    self.frame:SetScript("OnUpdate", onUpdate)
end

function Detector:Disable()
    if self.frame then
        self.frame:SetScript("OnUpdate", nil)
    end
    -- Turning monitoring off must cost nothing at all, so the ring stops
    -- receiving events rather than merely ignoring them.
    eventWatcher:UnregisterAllEvents()
    eventWatcher:SetScript("OnEvent", nil)

    severity, state = 0, STATE.CALM
    lastPushedState = nil
    ns.Overlay:ClearToasts()
    ns.Overlay:Refresh(STATE.CALM)
end

function Detector:StartGrace()
    graceUntil = GetTime() + DB.settings.zoneGraceSec
end

-- Read-only status accessor for the export report. Returns the current rolling
-- baseline frame time (ms) and whether it has finished warming up.
function Detector:GetStatus()
    return baselineMs, baselineReady
end