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
-- Chronic cost: what addons spend on every frame. Includes StutterAlert itself,
-- unlike the blame list.
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
-- Per-addon memory. UpdateAddOnMemoryUsage costs about 50 ms, so call this only
-- inside the loading-screen grace window. See DESIGN-NOTES.md: Memory sampling.
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
-- Secret values (12.0.7): comparing, arithmetic on, or testing the truth of a
-- secret raises. Records reach SavedVariables, so no secret may enter them; a
-- failed read degrades one field to its default.
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

-- Network context, declared before buildContext reads it.
-- See DESIGN-NOTES.md: Network and combat logging.
local LAT_SAMPLE_SEC     = 30    -- GetNetStats refreshes about this often
local LAT_MIN_SAMPLES    = 4     -- usual latency needs this many samples first
local LAT_HIGH_FLOOR_MS  = 150   -- a hitch is "high latency" at or above this
local LAT_HIGH_RATIO     = 2     -- and at least this many times the usual
local nextLatSample      = 0

local function worldLatency()
    local _, _, _, lw = GetNetStats()
    return lw
end

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

    -- Context shown to the player, never asserted as the cause. Every read goes
    -- through the secret-safe helpers.
    local nameplates = 0
    if C_NamePlate and C_NamePlate.GetNamePlates then
        local ok, plates = pcall(C_NamePlate.GetNamePlates)  -- 12.0.1: no args
        if ok and plates then nameplates = #plates end
    end

    local latencyWorld = safeNum(worldLatency, 0)

    -- nil until the usual latency is known, so early hitches stay uncounted.
    local latencyHigh
    local totals = DB.data and DB.data.totals
    if latencyWorld > 0 and totals and (totals.latN or 0) >= LAT_MIN_SAMPLES then
        local usual = totals.latSum / totals.latN
        latencyHigh = latencyWorld >= math.max(LAT_HIGH_FLOOR_MS, usual * LAT_HIGH_RATIO)
    end

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
        latencyHigh  = latencyHigh,
        combatLog    = safeBool(LoggingCombat, nil), -- nil where the API is missing
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
        label = format(L.CTX_WITH_COMBAT, label)
    end
    return label
end

function Detector:GetSeverityLabel()
    return L[ns.SEVERITY_LABEL[state] or "SEV_CALM"]
end

-- ---------------------------------------------------------------------------
-- Detection tuning. Not user-configurable, so every install measures the same
-- way and reports stay comparable.
-- ---------------------------------------------------------------------------
local LOADING_TAIL_SEC   = 5     -- a hitch within this long after a zone-in = streaming
local BASELINE_TAU_SEC   = 1.5   -- EMA time-constant for "normal" frame time
local WARMUP_SEC         = 2     -- learn this machine before trusting hitch shape
local SMOOTH_FLOOR_MS    = 33    -- ~30 fps; baseline at/above this = the machine is struggling
local SPIKE_RATIO        = 3     -- frame must reach baseline*this (floored at hitchThresholdMs) to count
local CLUSTER_WINDOW_SEC = 5     -- look-back window for repeated hitches
local CLUSTER_COUNT      = 4     -- this many hitches in the window = sustained, even if baseline lags
local SCENE_UNITS        = 8     -- this many nearby units at hitch time = the engine is loading models/effects

-- Throttle regime: a frame cap, told apart from a struggling machine by shape
-- (a cap is a metronome). See DESIGN-NOTES.md: Throttle regime.
local THROTTLE_FLOOR_MS  = 40    -- below ~25 fps before a regime is even considered
local THROTTLE_SPREAD    = 0.12  -- (max-min)/mean across the window; a cap sits near 0
local THROTTLE_CONFIRM   = 4     -- consecutive frames that must agree
local THROTTLE_CAP_TOL   = 0.08  -- how near 1000/cap a frame must land to corroborate
local THROTTLE_DROP_RATIO= 0.75  -- normal must have been this much faster than the background cap
local THROTTLE_TAIL_SEC  = 1     -- ignore hitches this long after the regime ends

-- ---------------------------------------------------------------------------
-- Frame-cap console variables. They only corroborate and name a regime the
-- shape already found; an unknown name drops out and the shape decides alone.
-- ---------------------------------------------------------------------------
local CAP_CVARS = { "maxFPSBk", "maxFPS" }

-- Kept apart from CAP_CVARS: see matchingForegroundCap.
local FG_CAP_CVARS = { "maxFPS" }

local function capPeriodMs(name)
    if not (C_CVar and C_CVar.GetCVarInfo) then return nil end
    local ok, value = pcall(C_CVar.GetCVarInfo, name)
    if not ok or value == nil then return nil end
    local fps = tonumber(value)
    -- 0 is how the client spells "no cap".
    if not fps or fps <= 0 then return nil end
    return 1000 / fps
end

-- Which configured cap, if any, this frame length matches. Returns the CVar name
-- and its frame period, or nil.
local function matchingCapIn(list, frameMs)
    for i = 1, #list do
        local name = list[i]
        local periodMs = capPeriodMs(name)
        if periodMs and math.abs(frameMs - periodMs) <= periodMs * THROTTLE_CAP_TOL then
            return name, periodMs
        end
    end
    return nil
end

-- Any configured cap this frame length matches. Used to NAME a regime the frame
-- shape has already identified, where either cap is a fair answer.
local function matchingCap(frameMs)
    return matchingCapIn(CAP_CVARS, frameMs)
end

-- Only the foreground cap may explain a baseline. Adding the background cap
-- here would call a player struggling at 30 fps "capped" (30 is its default).
-- See DESIGN-NOTES.md: Throttle regime.
local function matchingForegroundCap(frameMs)
    return matchingCapIn(FG_CAP_CVARS, frameMs)
end

-- ---------------------------------------------------------------------------
-- Throttle regime state. The ring holds the last THROTTLE_CONFIRM frame lengths
-- and is written every frame with no allocation.
-- ---------------------------------------------------------------------------
local frameRing      = {}
local frameRingPos   = 0
local frameRingCount = 0

local throttled      = false
local throttleCVar   = nil   -- the cap CVar that corroborated it, if any
local throttleUntil  = 0     -- resume grace: set when the regime ends

local function pushFrame(ms)
    frameRingPos = (frameRingPos % THROTTLE_CONFIRM) + 1
    frameRing[frameRingPos] = ms
    if frameRingCount < THROTTLE_CONFIRM then
        frameRingCount = frameRingCount + 1
    end
end

local function resetFrameRing()
    frameRingPos, frameRingCount = 0, 0
    for i = 1, THROTTLE_CONFIRM do frameRing[i] = nil end
end

-- Is the ring a metronome? Returns (isMetronome, mean frame ms), false until the
-- ring is full. No minimum length: steady 60 fps is a metronome too, and the
-- callers decide what it means.
local function ringShape()
    if frameRingCount < THROTTLE_CONFIRM then return false end
    local lo, hi, sum = math.huge, 0, 0
    for i = 1, THROTTLE_CONFIRM do
        local v = frameRing[i]
        if not v or v <= 0 then return false end
        if v < lo then lo = v end
        if v > hi then hi = v end
        sum = sum + v
    end
    local mean = sum / THROTTLE_CONFIRM
    if mean <= 0 then return false end
    return ((hi - lo) / mean) <= THROTTLE_SPREAD, mean
end

-- Is this metronome the background cap, so the window is not being watched?
-- A matching foreground cap excludes it: when both are equal, assume playing.
-- See DESIGN-NOTES.md: Throttle regime.
local function looksLikeBackgroundCap(meanMs)
    local bk = capPeriodMs("maxFPSBk")
    if not bk or math.abs(meanMs - bk) > bk * THROTTLE_CAP_TOL then return false end

    local fg = capPeriodMs("maxFPS")
    if fg and math.abs(meanMs - fg) <= fg * THROTTLE_CAP_TOL then return false end

    -- Tabbing out is a change: the baseline must have been faster than the cap.
    -- Without this, a player locked at 30 fps in the foreground loses monitoring.
    if not baselineReady or baselineMs <= 0 then return false end
    return baselineMs < bk * THROTTLE_DROP_RATIO
end

-- Seconds of frame time in the ring: monitored time banked before a regime was
-- confirmed, taken back so the per-minute rate excludes it.
local function ringSeconds()
    local sum = 0
    for i = 1, THROTTLE_CONFIRM do sum = sum + (frameRing[i] or 0) end
    return sum / 1000
end

-- ---------------------------------------------------------------------------
-- Non-addon cause: the locale key of the likeliest cause, most confident first.
-- Latency and average FPS are never causes. See DESIGN-NOTES.md: Cause ladder.
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

    -- 4. Machine struggling: ordinary frames are already slow. A foreground cap
    --    explains the baseline, not this frame, so it falls through.
    if baselineMs >= SMOOTH_FLOOR_MS and not matchingForegroundCap(baselineMs) then
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
-- Event ring: what was dispatched on the frame that hitched. Double buffered:
-- the hitch's events are always in the PREVIOUS bucket, never the current one.
-- See DESIGN-NOTES.md: Event ring.
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

-- Stale prefixes are not cleared: index i is read only when event i is
-- CHAT_MSG_ADDON, and then this frame wrote it.
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

    -- Empty, not nil: "nothing fired" is a finding (OnUpdate or timer work), and
    -- nil is reserved for a failed capture.
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

-- The most recently blamed addon, for co-occurrence: several addons spiking in
-- one cluster window usually share one trigger.
local lastBlamed, lastBlamedAt = nil, 0

-- ---------------------------------------------------------------------------
-- Deferred commit: a hitch is built at once but written only after
-- THROTTLE_CONFIRM frames prove it did not start a regime.
-- See DESIGN-NOTES.md: Deferred commit.
-- ---------------------------------------------------------------------------
local pending = {}

local function commitHitch(p)
    local s = DB.settings
    local rec = p.rec

    -- Leaky-bucket severity, applied on commit so a dropped candidate never
    -- tints the button. A worse hitch raises severity more.
    severity = severity + (p.frameMs - s.hitchThresholdMs) * s.severityGain

    DB:RecordHitch(rec)

    -- Surface this hitch as a toast banner. Repeated spikes from the same source
    -- coalesce into one banner (with an xN counter) that lives as long as the
    -- spikes keep coming, instead of stacking a fresh banner every frame.
    ns.Overlay:PushToast(p.toastKey, p.toastName, rec.isAddon, p.toastMs)

    if s.soundOnCritical and p.frameMs >= s.criticalFrameMs then
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON, "Master")
    end
end

-- Throw away everything still waiting: the frames they described turned out to
-- be the start of a throttle regime, not stutters.
local function discardPending()
    for i = #pending, 1, -1 do pending[i] = nil end
end

-- Commit anything that has now outlived the confirmation window.
local function flushPending(frameCount)
    -- Entries are appended in frame order, so the queue can always be drained
    -- from the front: the first one still too young means every later one is too.
    while pending[1] and (frameCount - pending[1].atFrame) >= THROTTLE_CONFIRM do
        commitHitch(table.remove(pending, 1))
    end
end

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

    -- This addon's share of the frame. The blame gate tests total addon time,
    -- so the share is what says how strong the evidence against one addon is.
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

    -- Events on the hitching frame, for every hitch. Guarded: payloads can be
    -- secret, and losing the list beats losing the hitch.
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

        -- Hitches sharing a signature collapse into one reported pattern. The
        -- top event is part of it; if it varies, the signature fragments, and
        -- that is the finding.
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

    -- Queued, not written. See the deferred-commit note above.
    pending[#pending + 1] = {
        rec       = rec,
        frameMs   = frameMs,
        atFrame   = self.frameCount,
        toastKey  = toastKey,
        toastName = toastName,
        toastMs   = toastMs,
    }
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

    -- A drop in Lua memory means a collection ran this frame. The same reads
    -- give the frame's allocation. See DESIGN-NOTES.md: Allocation buckets.
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

    -- Throttle regime, before anything is recorded. Feed the ring on every
    -- frame, hitches and grace included, or the shape test reads gaps.
    Detector.frameCount = (Detector.frameCount or 0) + 1
    pushFrame(frameMs)

    local totals = DB.data and DB.data.totals

    -- Suspend for a metronome at the background cap, or one slower than
    -- THROTTLE_FLOOR_MS (no cap variable readable). A foreground cap alone is
    -- not enough. See DESIGN-NOTES.md: Throttle regime.
    local metronome, ringMean = ringShape()
    local isRegime = metronome and
        (looksLikeBackgroundCap(ringMean) or ringMean >= THROTTLE_FLOOR_MS)

    if throttled then
        -- The moment the shape breaks, the regime is over: either the player came
        -- back to the window, or the cap changed, and in both cases the next few
        -- frames are genuinely long for reasons nobody should be blamed for.
        if not isRegime then
            throttled     = false
            throttleCVar  = nil
            throttleUntil = now + THROTTLE_TAIL_SEC
            ns.Overlay:SetThrottled(false)
        end
    elseif isRegime then
        throttled    = true
        throttleCVar = matchingCap(ringMean)

        -- Take back what was banked before the regime was confirmed: the
        -- candidate hitches queued during those frames, the cluster entries they
        -- created, and the monitored seconds they added.
        discardPending()
        hitchWindow = {}
        if totals then
            totals.throttledSec = (totals.throttledSec or 0) + ringSeconds()
            totals.monitoredSec = (totals.monitoredSec or 0) - ringSeconds()
            if totals.monitoredSec < 0 then totals.monitoredSec = 0 end
        end
        ns.Overlay:SetThrottled(true, throttleCVar)
    end

    -- Nothing is measured while capped or just after. The baseline stays frozen;
    -- drifting up to the cap would blind detection after tabbing back in.
    local inGrace = (now < graceUntil) or throttled or (now < throttleUntil)

    if throttled and totals then
        totals.throttledSec = (totals.throttledSec or 0) + elapsed
    end

    -- Monitored time and the usual-latency samples skip what detection skips.
    if not inGrace and totals then
        totals.monitoredSec = (totals.monitoredSec or 0) + elapsed
        if now >= nextLatSample then
            nextLatSample = now + LAT_SAMPLE_SEC
            local lw = safeNum(worldLatency, 0)
            if lw > 0 then
                totals.latSum = (totals.latSum or 0) + lw
                totals.latN   = (totals.latN or 0) + 1
            end
        end
    end

    -- Commit or drop candidates from earlier frames. Runs after the regime check
    -- above, so a candidate is only ever written once we know the frames that
    -- followed it were not the start of a cap.
    if inGrace then
        discardPending()
    else
        flushPending(Detector.frameCount)
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

    -- Throttle detection starts from no history, so a regime has to re-prove
    -- itself rather than being inherited from before monitoring was enabled.
    resetFrameRing()
    discardPending()
    self.frameCount = 0
    throttled, throttleCVar, throttleUntil = false, nil, 0
    ns.Overlay:SetThrottled(false)

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
    discardPending()
    resetFrameRing()
    throttled, throttleCVar, throttleUntil = false, nil, 0
    ns.Overlay:SetThrottled(false)
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

-- Is the client running to a deliberate cap, and which console variable
-- corroborated it? Detection is suspended while true, and the UI says so.
function Detector:IsThrottled()
    return throttled, throttleCVar
end

-- Is this machine's normal set by a foreground cap? Returns the console variable
-- and the frame rate it holds, or nil. Report only: detection is unaffected.
function Detector:GetBaselineCap()
    if not baselineReady or baselineMs <= 0 then return nil end
    local name, periodMs = matchingForegroundCap(baselineMs)
    if not name then return nil end
    return name, floor((1000 / periodMs) + 0.5)
end