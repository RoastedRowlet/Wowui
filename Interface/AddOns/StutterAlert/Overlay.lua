local _, ns = ...
local L     = ns.L
local DB    = ns.DB
local STATE = ns.STATE
local COLOR = ns.COLOR

local format  = string.format
local GetTime = GetTime

local Overlay = {}
ns.Overlay = Overlay

local BAR_HEIGHT  = 24
local BAR_WIDTH   = 190  -- min width for the (wider) pull-summary toast

-- Toast tuning (the stack lifecycle). Durations live in DB.settings so the
-- player can lengthen them; these are only the animation/spacing constants.
local TOAST_FADE_IN = 0.15  -- seconds to fade a new toast in
local TOAST_FADE    = 0.5   -- seconds to fade an expiring toast out
local TOAST_SPACING = 2     -- pixels between stacked toasts
local TOAST_PAD     = 4     -- pixels between the button and the nearest toast
local MIN_PULL_SEC  = 3     -- ignore combats shorter than this with no hitches

local frame, bg, dot, pulse
local inCombat = false

-- Toast stack state. ALL in-memory: toasts[1] is the newest (nearest the
-- button), older ones are pushed away in the active growth direction.
local toasts    = {}
local toastPool = {}
local driver    = CreateFrame("Frame")
driver:Hide()

-- ---------------------------------------------------------------------------
-- Toast frame pool (reuse frames; never create/destroy per toast)
-- ---------------------------------------------------------------------------
local function createToastFrame()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(90) -- sit just under the anchor button
    f:Hide()

    local tbg = f:CreateTexture(nil, "BACKGROUND")
    tbg:SetAllPoints()
    f.bg = tbg

    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("LEFT", f, "LEFT", 8, 0)
    fs:SetPoint("RIGHT", f, "RIGHT", -8, 0)
    f.label = fs

    return f
end

local function acquireToast()
    local f = table.remove(toastPool)
    if not f then f = createToastFrame() end
    f:SetAlpha(0)
    f:Show()
    return { frame = f }
end

local function releaseToast(t)
    if t and t.frame then
        t.frame:Hide()
        t.frame:ClearAllPoints()
        toastPool[#toastPool + 1] = t.frame
    end
end

local function enforceCap()
    local maxN = DB.settings.bannerStackMax or 4
    while #toasts > maxN do
        releaseToast(table.remove(toasts)) -- drop the oldest (end of the list)
    end
end

-- ---------------------------------------------------------------------------
-- Growth direction: shared by the toast stack and the tooltip anchor. Returns
-- (growsUp, alignRight). alignRight == true means "anchored on the right edge,
-- text right-justified, the stack grows to the left".
-- ---------------------------------------------------------------------------
local function getGrowthDir()
    local s = DB.settings
    local override = s.bannerGrowthOverride or "AUTO"
    if override == "LEFT_UP"    then return true,  true  end
    if override == "LEFT_DOWN"  then return false, true  end
    if override == "RIGHT_UP"   then return true,  false end
    if override == "RIGHT_DOWN" then return false, false end

    -- AUTO: derive from where the button sits on screen.
    local growsUp, alignRight = false, true
    if frame then
        local x, y = frame:GetCenter()
        local screenW, screenH = UIParent:GetRight(), UIParent:GetTop()
        if y and screenH then growsUp = not (y > (screenH / 2)) end
        if Overlay.dockedSide == "RIGHT" then
            alignRight = true
        elseif Overlay.dockedSide == "LEFT" then
            alignRight = false
        elseif x and screenW then
            alignRight = x > (screenW / 2)
        end
    end
    return growsUp, alignRight
end

-- "StutterAlert vX" for the tooltip header and export dialog (one source of truth).
local function versionedTitle()
    local ver = C_AddOns.GetAddOnMetadata("StutterAlert", "Version") or L.UNKNOWN_SOURCE
    return format(L.TITLE_VERSION, L.TT_TITLE, ver)
end

-- ---------------------------------------------------------------------------
-- Position
-- ---------------------------------------------------------------------------
function Overlay:LayoutToasts()
    if not frame or #toasts == 0 then return end
    local growsUp, alignRight = getGrowthDir()

    for i = 1, #toasts do
        local f = toasts[i].frame
        f:ClearAllPoints()
        f.label:SetJustifyH(alignRight and "RIGHT" or "LEFT")

        local myCorner, anchorCorner, yOff
        if growsUp then
            myCorner     = alignRight and "BOTTOMRIGHT" or "BOTTOMLEFT"
            anchorCorner = alignRight and "TOPRIGHT"    or "TOPLEFT"
            yOff = (i == 1) and TOAST_PAD or TOAST_SPACING
        else
            myCorner     = alignRight and "TOPRIGHT"    or "TOPLEFT"
            anchorCorner = alignRight and "BOTTOMRIGHT" or "BOTTOMLEFT"
            yOff = (i == 1) and -TOAST_PAD or -TOAST_SPACING
        end

        if i == 1 then
            f:SetPoint(myCorner, frame, anchorCorner, 0, yOff)
        else
            f:SetPoint(myCorner, toasts[i - 1].frame, anchorCorner, 0, yOff)
        end
    end
end

function Overlay:RestorePosition()
    if not frame then return end
    local s = DB.settings
    local GAP = 4  -- pixels between the micro button and the pill
    frame:ClearAllPoints()

    -- Default size fallback using user settings
    local btnSize = s.buttonSize
    if not btnSize then btnSize = "DEFAULT" end

    -- User-dragged custom position
    if not s.usingDefaultAnchor then
        local actualSize = (btnSize == "DEFAULT") and 32 or btnSize
        frame:SetPoint(s.point, UIParent, s.relativePoint, s.x, s.y)
        frame:SetSize(actualSize, actualSize)
        self.dockedSide = nil
        if #toasts > 0 then self:LayoutToasts() end
        return
    end

    local helpBtn = MainMenuMicroButton
    local charBtn = CharacterMicroButton
    local actualSize = btnSize

    if helpBtn and charBtn then
        if actualSize == "DEFAULT" then
            -- Dynamically match the height of the micro button to look native
            local height = helpBtn:GetHeight()
            if height and height > 0 then
                actualSize = height
            else
                actualSize = 32
            end
        end

        -- Determine actual rightmost and leftmost buttons in the cluster
        local rightTarget = helpBtn
        local leftTarget = charBtn

        -- Prevent LFG Eye collision: If the QueueStatusButton is visible and
        -- physically close to the micro menu, extend our anchor target to include it.
        if QueueStatusButton and QueueStatusButton:IsShown() then
            local hx, hy = helpBtn:GetCenter()
            local cx, cy = charBtn:GetCenter()
            local qx, qy = QueueStatusButton:GetCenter()

            -- Check if LFG eye is clustered near the right side
            if hx and qx and hy and qy and math.abs(hx - qx) < 150 and math.abs(hy - qy) < 150 then
                local qRight, hRight = QueueStatusButton:GetRight(), helpBtn:GetRight()
                if qRight and hRight and qRight > hRight then
                    rightTarget = QueueStatusButton
                end
            end

            -- Check if LFG eye is clustered near the left side
            if cx and qx and cy and qy and math.abs(cx - qx) < 150 and math.abs(cy - qy) < 150 then
                local qLeft, cLeft = QueueStatusButton:GetLeft(), charBtn:GetLeft()
                if qLeft and cLeft and qLeft < cLeft then
                    leftTarget = QueueStatusButton
                end
            end
        end

        local helpRight = rightTarget:GetRight()
        local screenW   = UIParent:GetRight()

        local roomRight = true
        if helpRight and screenW then
            roomRight = (helpRight + GAP + BAR_WIDTH) <= screenW
        end

        if roomRight then
            -- Middle vertical align to the RIGHT of the rightmost icon
            frame:SetPoint("LEFT", rightTarget, "RIGHT", GAP, 0)
            self.dockedSide = "RIGHT"
        else
            -- Middle vertical align to the LEFT of the leftmost icon
            frame:SetPoint("RIGHT", leftTarget, "LEFT", -GAP, 0)
            self.dockedSide = "LEFT"
        end
    else
        -- Defensive fallback
        if actualSize == "DEFAULT" then actualSize = 32 end
        frame:SetPoint("TOP", UIParent, "TOP", 0, -200)
        self.dockedSide = nil
    end

    frame:SetSize(actualSize, actualSize)

    -- If the anchor shifts while toasts are visible (e.g. queue pops mid-stutter), redraw them
    if #toasts > 0 then
        self:LayoutToasts()
    end
end

local function savePosition()
    local s = DB.settings
    local left, bottom = frame:GetLeft(), frame:GetBottom()
    if not left or not bottom then return end
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
    s.usingDefaultAnchor = false
    s.point, s.relativePoint = "BOTTOMLEFT", "BOTTOMLEFT"
    s.x, s.y = left, bottom
end

function Overlay:ResetPosition()
    DB.settings.usingDefaultAnchor = true
    DB.settings.bannerGrowthOverride = "AUTO"
    DB.settings.buttonSize = "DEFAULT"
    DB.settings.locked = true
    self:RestorePosition()
    self:UpdateMouse()
end

-- ---------------------------------------------------------------------------
-- Mouse / combat behavior
-- ---------------------------------------------------------------------------
-- Locked + in combat  -> click-through (rely on the auto-surfacing readout).
-- Locked + out of combat -> interactive (hover tooltip works).
-- Unlocked -> interactive (so it can be dragged).
function Overlay:UpdateMouse()
    if not frame then return end
    -- Always enable the mouse so tooltips can be viewed at any time, even in combat.
    -- Dragging is independently prevented by DB.settings.locked inside OnDragStart.
    frame:EnableMouse(true)
end

function Overlay:SetCombat(state)
    inCombat = state and true or false
    self:UpdateMouse()
end

function Overlay:SetLocked(locked)
    DB.settings.locked = locked and true or false
    self:UpdateMouse()
end

-- ---------------------------------------------------------------------------
-- Tooltip (built on demand, only when hovered)
-- ---------------------------------------------------------------------------
local function formatTimeAgo(timestamp)
    local diff = time() - timestamp
    if diff < 60 then
        return format(L.TT_TIME_SEC, diff)
    elseif diff < 3600 then
        return format(L.TT_TIME_MIN, math.floor(diff / 60))
    else
        return format(L.TT_TIME_HOUR, math.floor(diff / 3600))
    end
end

local function getMsColor(ms)
    local s = DB.settings
    if ms >= s.criticalFrameMs then
        local c = COLOR[STATE.CRITICAL]
        return c[1], c[2], c[3]
    elseif ms >= s.hitchThresholdMs then
        local c = COLOR[STATE.ELEVATED]
        return c[1], c[2], c[3]
    else
        local c = COLOR[STATE.CALM]
        return c[1], c[2], c[3]
    end
end

-- Plain-English definition shown for the newest hitch (one per confidence tier).
local CAUSE_DEF = {
    HEADLINE_LOADING   = "DEF_LOADING",
    HEADLINE_GC        = "DEF_GC",
    HEADLINE_SUSTAINED = "DEF_SUSTAINED",
    HEADLINE_SCENE     = "DEF_SCENE",
    HEADLINE_COMBAT_FX = "DEF_COMBAT_FX",
    HEADLINE_STREAMING = "DEF_STREAMING",
    HEADLINE_ENGINE    = "DEF_ENGINE",
    HEADLINE_UNCLEAR   = "DEF_UNCLEAR",
}

local function defKeyFor(r)
    if r.isAddon then return "DEF_ADDON" end
    return CAUSE_DEF[r.causeKey or "HEADLINE_ENGINE"] or "DEF_ENGINE"
end

-- "While this happened: ..." line, assembled from the conditions captured at
-- hitch time. These are CONTEXT to help the player decide, never the verdict.
local function buildContextLine(r)
    local ctx = r.ctx
    if not ctx then return nil end

    local parts = {}
    parts[#parts + 1] = L[ns.CONTEXT_LABEL[r.ctxKey or "world"] or "CTX_WORLD"]
    if ctx.inCombat then
        parts[#parts + 1] = L.TT_CTX_COMBAT
    end
    if ctx.nameplates and ctx.nameplates >= 5 then
        parts[#parts + 1] = format(L.TT_CTX_ENEMIES, ctx.nameplates)
    end
    if ctx.latencyWorld and ctx.latencyWorld >= 150 then
        parts[#parts + 1] = format(L.TT_CTX_LATENCY, ctx.latencyWorld)
    end

    return format(L.TT_CTX_PREFIX, table.concat(parts, ", "))
end

local function showTooltip()
    -- Anchor the tooltip on whichever side the stack is NOT growing into.
    local _, alignRight = getGrowthDir()
    if alignRight then
        GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    else
        GameTooltip:SetOwner(frame, "ANCHOR_LEFT")
    end

    GameTooltip:AddLine(versionedTitle())

    -- Severity label (color = severity, matching the button).
    local st = ns.Overlay.currentState or STATE.CALM
    local sc = COLOR[st]
    GameTooltip:AddLine(format(L.TT_SEVERITY, ns.Detector:GetSeverityLabel()), sc[1], sc[2], sc[3])
    GameTooltip:AddLine(" ")

    -- Last 5 pulls this session (in-memory only; gone on reload/logout).
    GameTooltip:AddLine(L.TT_PULLS_HEADER)
    local pulls = DB:GetRecentPulls()
    if #pulls == 0 then
        GameTooltip:AddLine(L.TT_PULLS_NONE, 0.6, 0.6, 0.6)
    else
        for i = 1, #pulls do
            local p = pulls[i]
            local timeAgo = formatTimeAgo(p.endedAt)
            local right
            if p.total == 0 then
                right = L.TT_PULL_CLEAN
            else
                right = format(L.TT_PULL_LINE, p.total, p.gameCount, p.addonCount, p.worstAnyMs)
            end
            local rCol, gCol, bCol = getMsColor(p.worstAnyMs or 0)
            GameTooltip:AddDoubleLine(timeAgo, right, 0.9, 0.9, 0.9, rCol, gCol, bCol)
        end
    end
    GameTooltip:AddLine(" ")

    GameTooltip:AddLine(L.TT_RECENT_HEADER)
    local recent = DB:GetRecentHitches(5)
    local seenCauses = {} -- non-addon causes, drives the actionable tips section
    local shownDefs  = {} -- so each distinct label is explained once, not per line

    if #recent == 0 then
        GameTooltip:AddLine(L.TT_RECENT_NONE, 0.6, 0.6, 0.6)
    else
        for i = 1, #recent do
            local r = recent[i]
            local timeAgo = formatTimeAgo(r.t)

            -- WoW glyph marks a game/engine cause; a named addon shows no glyph.
            -- Name is neutral (color stripped). Right-side color = HOW BAD.
            local who, rightText
            if r.isAddon then
                who = ns.AddonGlyph(r.culprit) .. " " .. ns.StripColor(r.culpritTitle or r.culprit or L.UNKNOWN_SOURCE)
                if r.culpritMult and r.culpritMult >= 2 then
                    rightText = format(L.TT_RECENT_RIGHT_MULT, r.ms, math.floor(r.culpritMult + 0.5), timeAgo)
                else
                    rightText = format(L.TT_RECENT_RIGHT, r.ms, ns.ContextLabelFor(r), timeAgo)
                end
            else
                who = ns.GLYPH_GAME .. " " .. L[r.causeKey or "HEADLINE_ENGINE"]
                rightText = format(L.TT_RECENT_RIGHT, r.ms, ns.ContextLabelFor(r), timeAgo)
                if r.causeKey then seenCauses[r.causeKey] = true end
            end

            local rCol, gCol, bCol = getMsColor(r.ms)
            GameTooltip:AddDoubleLine(who, rightText, 0.9, 0.9, 0.9, rCol, gCol, bCol)

            -- Newest hitch: show what was happening at the time.
            if i == 1 then
                local ctxLine = buildContextLine(r)
                if ctxLine then
                    GameTooltip:AddLine(ctxLine, 0.6, 0.6, 0.6, true)
                end
            end

            -- Explain every distinct label the player can see, once each, inline.
            local dk = defKeyFor(r)
            if not shownDefs[dk] then
                shownDefs[dk] = true
                GameTooltip:AddLine(L[dk], 0.6, 0.6, 0.6, true)
            end
        end
    end

    local top = DB:GetTopSources(5)
    if #top > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L.TT_TOP_HEADER)
        for i = 1, #top do
            local e = top[i]
            local title = ns.AddonGlyph(e.name) .. " " .. ns.StripColor(ns.addonTitle[e.name] or e.name)
            local timeAgo = formatTimeAgo(e.peakTime or time())
            local rightText = format(L.TT_TOP_RIGHT, e.hitches, e.peakMs, timeAgo)
            local rCol, gCol, bCol = getMsColor(e.peakMs)

            GameTooltip:AddDoubleLine(title, rightText, 0.9, 0.9, 0.9, rCol, gCol, bCol)
        end
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L.TT_HITCH_EXPLAIN, 1, 0.82, 0, true)
    GameTooltip:AddLine(L.TT_ACTION_HEADER, 0.9, 0.9, 0.9)
    GameTooltip:AddLine(L.TT_ACTION_ADDON, 0.8, 0.8, 0.8, true)

    local addedTips = false
    for causeKey in pairs(seenCauses) do
        local tipKey = causeKey .. "_TIP"
        local tipText = L[tipKey]
        if tipText and tipText ~= tipKey then
            GameTooltip:AddLine("- " .. tipText, 0.8, 0.8, 0.8, true)
            addedTips = true
        end
    end

    if not addedTips then
        GameTooltip:AddLine(L.TT_ACTION_ENGINE, 0.8, 0.8, 0.8, true)
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L.TT_HINT_EXPORT, 0.5, 0.5, 0.5)
    GameTooltip:AddLine(L.TT_HINT_CLEAR, 0.5, 0.5, 0.5)
    GameTooltip:AddLine(L.TT_HINT_MENU, 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

-- ---------------------------------------------------------------------------
-- Toast stack: render, push, coalesce, expire
-- ---------------------------------------------------------------------------
-- Compose and color one toast frame from its record.
function Overlay:RenderToast(t)
    local f = t.frame
    local text, r, g, b

    if t.isSummary then
        text = t.text
        local c = t.color or COLOR[STATE.ELEVATED]
        r, g, b = c[1], c[2], c[3]
        -- Distinct, slightly cooler/darker fill so pull summaries read apart
        -- from live hitch banners.
        f.bg:SetColorTexture(0.08, 0.08, 0.12, 0.95)
    else
        if t.count > 1 then
            text = format(L.TOAST_MANY, t.name, t.count, t.peakMs)
        else
            text = format(L.TOAST_ONE, t.name, t.peakMs)
        end
        -- Game/engine causes get the WoW glyph; an addon gets its own logo
        -- (or a generic marker when it declares no icon).
        if t.isAddon then
            text = ns.AddonGlyph(t.key) .. " " .. text
        else
            text = ns.GLYPH_GAME .. " " .. text
        end
        r, g, b = getMsColor(t.peakMs)
        f.bg:SetColorTexture(0.05, 0.05, 0.05, 0.9)
    end

    f.label:SetText(text)
    f.label:SetTextColor(r, g, b)

    local w = (f.label:GetStringWidth() or 0) + 16
    local minW = t.isSummary and BAR_WIDTH or 60
    if w < minW then w = minW end
    f:SetSize(w, BAR_HEIGHT)
end

-- Push (or coalesce) a live hitch toast. Repeats of the same `key` bump the
-- existing toast's counter/peak and refresh its timer instead of stacking.
function Overlay:PushToast(key, name, isAddon, ms)
    if not frame then return end
    ms = ms or 0
    local now = GetTime()

    for i = 1, #toasts do
        local t = toasts[i]
        if not t.isSummary and t.key == key then
            t.count  = t.count + 1
            if ms > t.peakMs then t.peakMs = ms end
            t.expiresAt = now + t.hold
            if i > 1 then -- promote to newest (nearest the button)
                table.remove(toasts, i)
                table.insert(toasts, 1, t)
            end
            self:RenderToast(t)
            self:LayoutToasts()
            return
        end
    end

    local t = acquireToast()
    t.isSummary = false
    t.key       = key
    t.name      = name
    t.isAddon   = isAddon and true or false
    t.peakMs    = ms
    t.count     = 1
    t.bornAt    = now
    t.hold      = DB.settings.bannerHoldSec or 10
    t.expiresAt = now + t.hold

    table.insert(toasts, 1, t)
    enforceCap()
    self:RenderToast(t)
    driver:Show()
    self:LayoutToasts()
end

-- Push a pull-summary toast: distinct styling, longer hold, never coalesced.
function Overlay:PushSummaryToast(text, color, holdOverride)
    if not frame then return end
    local now = GetTime()

    local t = acquireToast()
    t.isSummary = true
    t.key       = nil
    t.text      = text
    t.color     = color
    t.count     = 1
    t.bornAt    = now
    t.hold      = holdOverride or DB.settings.summaryHoldSec or 14
    t.expiresAt = now + t.hold

    table.insert(toasts, 1, t)
    enforceCap()
    self:RenderToast(t)
    driver:Show()
    self:LayoutToasts()
end

-- Driver tick: fade toasts in/out and reap expired ones. Runs only while the
-- stack is non-empty (the driver hides itself when it empties).
function Overlay:UpdateToasts()
    local now = GetTime()
    local changed = false

    for i = #toasts, 1, -1 do
        local t = toasts[i]
        local f = t.frame
        if now >= t.expiresAt then
            local fadeAge = now - t.expiresAt
            if fadeAge >= TOAST_FADE then
                releaseToast(t)
                table.remove(toasts, i)
                changed = true
            else
                f:SetAlpha(1 - fadeAge / TOAST_FADE)
            end
        else
            local age = now - t.bornAt
            if age < TOAST_FADE_IN then
                f:SetAlpha(age / TOAST_FADE_IN)
            else
                f:SetAlpha(1)
            end
        end
    end

    if changed then self:LayoutToasts() end
    if #toasts == 0 then driver:Hide() end
end

driver:SetScript("OnUpdate", function() Overlay:UpdateToasts() end)

function Overlay:ClearToasts()
    for i = #toasts, 1, -1 do
        releaseToast(toasts[i])
        toasts[i] = nil
    end
    driver:Hide()
end

-- ---------------------------------------------------------------------------
-- Visual state: the button tint only. Banners are the toast stack now.
-- ---------------------------------------------------------------------------
function Overlay:Refresh(state)
    if not frame then return end
    self.currentState = state or STATE.CALM

    -- Color = severity, always. The SA logo just tints to how-bad.
    local c = COLOR[self.currentState]
    bg:SetVertexColor(c[1], c[2], c[3], 1.0)

    if self.currentState == STATE.CRITICAL then
        if not pulse:IsPlaying() then pulse:Play() end
    elseif pulse:IsPlaying() then
        pulse:Stop()
    end
end

-- ---------------------------------------------------------------------------
-- Post-pull summary: pushed automatically when leaving combat. Also feeds the
-- in-memory "last 5 pulls" ring shown in the tooltip.
-- ---------------------------------------------------------------------------
function Overlay:ShowPullSummary(sinceTime)
    if not frame then return end

    local sum = DB:Summarize(sinceTime)
    local duration = time() - (sinceTime or time())

    -- Ignore trivial taps that produced nothing (dummy hits, instant procs).
    if duration < MIN_PULL_SEC and sum.total == 0 then return end

    local gameCount = sum.total - sum.addonCount

    -- Record into the session-only ring (never saved) for the tooltip.
    DB:RecordPull({
        endedAt    = time(),
        total      = sum.total,
        addonCount = sum.addonCount,
        gameCount  = gameCount,
        worstAnyMs = sum.worstAnyMs,
        worstTitle = sum.worstTitle,
        worstMs    = sum.worstMs,
    })

    local text
    if sum.total == 0 then
        text = L.SUMMARY_PULL_CLEAN
    elseif sum.worstTitle then
        local worst = ns.StripColor(sum.worstTitle)
        if sum.worstCulprit then worst = ns.AddonGlyph(sum.worstCulprit) .. " " .. worst end
        text = format(L.SUMMARY_PULL_WORST, sum.total, worst, sum.worstMs, gameCount)
    else
        text = format(L.SUMMARY_PULL, sum.total, sum.addonCount, gameCount)
    end

    -- Color by the worst single frame seen in the window (any cause), so an
    -- engine-only pull still reads as a real event instead of "calm".
    local c
    if sum.total == 0 then
        c = COLOR[STATE.CALM]
    elseif sum.worstAnyMs >= DB.settings.criticalFrameMs then
        c = COLOR[STATE.CRITICAL]
    else
        c = COLOR[STATE.ELEVATED]
    end

    self:PushSummaryToast(text, c)
end

-- ---------------------------------------------------------------------------
-- Shareable diagnostic report (left-click the button while locked).
--
-- The report has no options, so it has to do the filtering a settings panel
-- would otherwise do: every source gets one summary line, and only sources with
-- something genuinely abnormal about them earn a detail block. Repeated hitches
-- that share a signature collapse into one stated pattern rather than N
-- identical-looking lines.
-- ---------------------------------------------------------------------------
local floor = math.floor

-- Does this source warrant the full breakdown, or just a summary line?
--
-- Deliberately strict: either it happened more than once (so there is a pattern
-- worth describing) or the single occurrence genuinely hurt. A one-off 80 ms
-- spike does not earn eight lines of evidence, and letting it would turn a
-- five-source report into forty lines nobody reads.
local function isNotable(agg)
    if (agg.hitches or 0) >= 2 then return true end
    if (agg.peakMs or 0) >= DB.settings.criticalFrameMs then return true end
    return false
end

-- "Dungeon / M+ x4, City x1", biggest bucket first.
local function contextSummary(agg)
    local parts = {}
    for key, n in pairs(agg.ctx or {}) do
        parts[#parts + 1] = { key = key, n = n }
    end
    if #parts == 0 then return nil end
    table.sort(parts, function(a, b) return a.n > b.n end)

    local out = {}
    for i = 1, #parts do
        out[#out + 1] = format(L.EXPORT_D_CTX,
            L[ns.CONTEXT_LABEL[parts[i].key] or "CTX_WORLD"], parts[i].n)
    end
    return table.concat(out, L.LIST_SEP)
end

-- Turn a stored signature key back into a readable phrase. The key is built in
-- the Detector as "<ctxKey>/<combat|calm>/<ALLOC_*>", and the allocation part is
-- already a locale key.
local function signatureText(sigKey)
    -- The trailing event segment is optional so signatures recorded before the
    -- event ring existed still render instead of silently vanishing.
    local ctxKey, combat, alloc, event =
        string.match(sigKey, "^([^/]+)/([^/]+)/([^/]+)/?(.*)$")
    if not ctxKey then return nil end

    local parts = {
        L[ns.CONTEXT_LABEL[ctxKey] or "CTX_WORLD"],
        (combat == "combat") and L.EXPORT_SIG_COMBAT or L.EXPORT_SIG_CALM,
        L[alloc],
    }
    if event and event ~= "" and event ~= "-" then
        parts[#parts + 1] = format(L.EXPORT_SIG_EVENT, event)
    end
    return table.concat(parts, L.LIST_SEP)
end

-- "CHAT_MSG_ADDON x37, GROUP_ROSTER_UPDATE" from a stored event summary.
local function eventListText(ev)
    if not ev or not ev.list or #ev.list == 0 then return nil end
    local out = {}
    for i = 1, #ev.list do
        out[#out + 1] = format(L.EXPORT_D_EV_ITEM, ev.list[i].name, ev.list[i].n)
    end
    return table.concat(out, L.LIST_SEP)
end

-- The evidence block for one notable source. Every line is conditional: we say
-- only what we actually measured, and stay silent rather than pad the report.
local function appendDetail(add, name, agg)
    -- The library caveat comes FIRST. It changes how everything below should be
    -- read, so it cannot sit underneath the evidence it qualifies.
    if ns.IsLibraryPackage(name) then
        local host = ns.LibraryHostOf(name)
        if host then
            add(format(L.EXPORT_D_LIBRARY_HOST, ns.StripColor(host)))
        else
            add(L.EXPORT_D_LIBRARY)
        end
    end

    local sigKey, sigN = DB:GetDominantSignature(agg)
    local sigCoversAll = false

    if sigKey then
        local text = signatureText(sigKey)
        if text then
            if sigN >= (agg.hitches or 0) then
                sigCoversAll = true
                add(format(L.EXPORT_D_SIG_ALL, agg.hitches, text))
            else
                add(format(L.EXPORT_D_SIG, sigN, agg.hitches, text))
            end
        end
    end

    -- The signature already names the context when it covers every hitch, so
    -- repeating it as a "Where" line would just be the same fact twice.
    if not sigCoversAll then
        local where = contextSummary(agg)
        if where then add(format(L.EXPORT_D_WHERE, where)) end
    end

    -- The share can exceed 100%: the addon's time comes from the profiler while
    -- the frame length comes from OnUpdate's elapsed, and the two clocks do not
    -- have to agree on a short frame. Printing "167% of the frame" would be
    -- plainly impossible and would discredit every other figure here, so above
    -- 100% we state only what we can defend.
    if agg.peakShare and agg.peakShare > 0 then
        if agg.peakShare > 1.05 then
            add(L.EXPORT_D_SHARE_ALL)
        else
            add(format(L.EXPORT_D_SHARE, floor(agg.peakShare * 100 + 0.5)))
        end
    end

    if agg.peakMult and agg.peakMult >= 2 then
        add(format(L.EXPORT_D_MULT, floor(agg.peakMult + 0.5)))
    end

    if agg.peakAllocAt and agg.peakAllocAt > 0 then
        local sizeText = ns.FormatKB(agg.peakAllocAt)
        if sizeText then add(format(L.EXPORT_D_ALLOC, sizeText)) end
    end

    -- What the game was dispatching. Placed directly under the cost evidence
    -- because for an event-driven addon this is usually the actual lead.
    local peakEv = agg.peakEv
    if peakEv then
        local evText = eventListText(peakEv)
        if evText then
            add(format(L.EXPORT_D_EV_PEAK, evText))
        elseif (peakEv.total or 0) == 0 and (peakEv.over or 0) == 0 then
            -- Nothing fired, which rules out an event handler and points at an
            -- OnUpdate or a timer. A nil peakEv means capture failed and is not
            -- the same claim, so it stays silent.
            add(L.EXPORT_D_EV_NONE)
        end
        if (peakEv.over or 0) > 0 then
            add(format(L.EXPORT_D_EV_BURST, peakEv.over))
        end
    end

    -- Skipped when the signature already named this event as the trigger, which
    -- is the common case for a genuinely repeating fault.
    local evName, evN = DB:GetDominantEvent(agg)
    if evName and not (sigKey and sigKey:find(evName, 1, true)) then
        add(format(L.EXPORT_D_EV_COMMON, evN, agg.hitches, evName))
    end

    local prefix, prefixN = DB:GetDominantPrefix(agg)
    if prefix then
        add(format(L.EXPORT_D_EV_PREFIX, prefix, prefixN))
    end

    local period = DB:GetPeriod(agg)
    if period then
        add(format(L.EXPORT_D_PERIOD, floor(period + 0.5)))
    end

    local over = agg.peakOver
    if over and (over[2] or 0) > 0 then
        add(format(L.EXPORT_D_OVER, over[2] or 0, over[3] or 0))
        -- Explain the gap when the client's count dwarfs ours, otherwise "47
        -- frames over 100 ms" beside "peak 95 ms" reads as a contradiction.
        if over[2] > ((agg.hitches or 0) * 2) then
            add(L.EXPORT_D_OVER_NOTE)
        end
    end

    local coName, coN = DB:GetTopCoOccurrence(agg)
    if coName then
        add(format(L.EXPORT_D_CO,
            ns.StripColor(ns.addonTitle[coName] or coName), coN))
    end

    -- Version drift. An author reading this needs to know whether the hitches
    -- predate a build they already fixed.
    local liveVer = ns.AddonVersion(name)
    if agg.firstVer and agg.lastVer and agg.firstVer ~= agg.lastVer then
        add(format(L.EXPORT_D_VER_SPAN, agg.firstVer, agg.lastVer))
    elseif liveVer and agg.lastVer and liveVer ~= agg.lastVer then
        add(format(L.EXPORT_D_VER_NOW, agg.lastVer, liveVer))
    end

    local mem = DB:GetMemory(name)
    if mem and mem.kb then
        local memText  = ns.FormatKB(mem.kb)
        -- Only call out growth worth noticing; ordinary churn is not a finding.
        local growText = (mem.delta and mem.delta > 512) and ns.FormatKB(mem.delta) or nil
        if memText and growText then
            add(format(L.EXPORT_D_MEM_GROW, memText, growText))
        elseif memText then
            add(format(L.EXPORT_D_MEM, memText))
        end
    end
end

function Overlay:BuildExportReport()
    local lines = {}
    local function add(s) lines[#lines + 1] = s or "" end

    add(versionedTitle())

    -- GetBuildInfo returns version, build, date, tocversion, ...
    local clientVer, clientBuild = GetBuildInfo()
    add(format(L.EXPORT_CLIENT, tostring(clientVer), tostring(clientBuild)))
    add(L.EXPORT_SCOPE)
    add("")

    -- All figures come from the lifetime tallies so they reconcile: the TL;DR,
    -- the per-cause counts, and Top Sources all share one window.
    local sum = DB:GetTotals()
    if sum.total == 0 then
        add(L.EXPORT_TLDR_CLEAN)
    else
        add(format(L.EXPORT_TLDR, sum.total, sum.addonCount, sum.gameCount))
        if sum.worstTitle then
            if sum.worstMult and sum.worstMult >= 2 then
                add(format(L.EXPORT_WORST, ns.StripColor(sum.worstTitle), sum.worstMs, floor(sum.worstMult + 0.5)))
            else
                add(format(L.EXPORT_WORST_NOMULT, ns.StripColor(sum.worstTitle), sum.worstMs))
            end
        end

        -- The denominator. A hitch count on its own cannot be judged, and a
        -- reader comparing two reports has no way to scale them without it.
        local monitored = DB.data.totals.monitoredSec
        if monitored and monitored >= 60 then
            local durText = ns.FormatDuration(monitored)
            if durText then
                add(format(L.EXPORT_SPAN, durText, sum.total / (monitored / 60)))
            end
        end
    end

    -- Constant cost. Stutters are only half the story: an addon burning a few ms
    -- of every frame never trips the hitch threshold but still eats the budget,
    -- and nothing in the addon reported that before.
    local chronic, chronicSum = ns.Detector:GetChronicCost(5)
    if chronicSum and chronicSum > 0 then
        add("")
        add(L.EXPORT_CHRONIC_HEADER)
        add(format(L.EXPORT_CHRONIC_TOTAL, chronicSum))
        for i = 1, #chronic do
            local c = chronic[i]
            add(format(L.EXPORT_CHRONIC_LINE,
                ns.StripColor(ns.addonTitle[c.name] or c.name), c.ms))
        end
    end

    local top = DB:GetTopSources(5)
    if #top > 0 then
        add("")
        add(L.EXPORT_TOP_HEADER)
        for i = 1, #top do
            local e = top[i]
            local agg = e.agg
            local title = ns.StripColor(ns.addonTitle[e.name] or e.name)
            local vstr = agg.lastVer or ns.AddonVersion(e.name)

            if e.hitches == 1 then
                if vstr then
                    add(format(L.EXPORT_TOP_LINE_VER_ONE, title, vstr, e.peakMs))
                else
                    add(format(L.EXPORT_TOP_LINE_ONE, title, e.peakMs))
                end
            elseif vstr then
                add(format(L.EXPORT_TOP_LINE_VER, title, vstr, e.hitches, e.peakMs))
            else
                add(format(L.EXPORT_TOP_LINE, title, e.hitches, e.peakMs))
            end

            if isNotable(agg) then
                appendDetail(add, e.name, agg)
            end
        end
    end

    -- Sorted biggest-first: pairs() order is arbitrary, which made the previous
    -- report list causes in a different order every time it was generated.
    local causeArr = {}
    for causeKey, n in pairs(sum.causes) do
        causeArr[#causeArr + 1] = { key = causeKey, n = n }
    end
    if #causeArr > 0 then
        table.sort(causeArr, function(a, b) return a.n > b.n end)
        add("")
        add(L.EXPORT_CAUSES_HEADER)
        for i = 1, #causeArr do
            add(format(L.EXPORT_CAUSE_LINE, L[causeArr[i].key], causeArr[i].n))
        end
    end

    local baseline, ready = ns.Detector:GetStatus()
    add("")
    if ready then
        add(format(L.EXPORT_BASELINE, floor((baseline or 0) + 0.5)))
    else
        add(L.EXPORT_BASELINE_WARMING)
    end

    add("")
    add(L.EXPORT_FOOTER)

    return table.concat(lines, "\n")
end

-- Landscape diagnostic panel: left 2/3 teaches "why & what to try" (from the
-- Advisor), right 1/3 is the shareable copy/paste report. Built once, lazily.
function Overlay:ShowExport()
    if not self.panelFrame then
        local PANEL_W, PANEL_H = 860, 520
        local LEFT_RIGHT = 568        -- x of the divider between the two columns
        local LEFT_SCROLL_W = 540     -- left scroll frame width
        local LEFT_TEXT_W = 510       -- wrap width of the advice text (clears the scrollbar)

        local f = CreateFrame("Frame", "StutterAlertPanel", UIParent)
        f:SetSize(PANEL_W, PANEL_H)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)

        local bgTex = f:CreateTexture(nil, "BACKGROUND")
        bgTex:SetAllPoints()
        bgTex:SetColorTexture(0.05, 0.05, 0.05, 0.95)

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 12, -10)
        title:SetText(versionedTitle())

        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 0, 0)

        -- LEFT column: advice text inside a scroll frame.
        local lsf = CreateFrame("ScrollFrame", "StutterAlertAdviceScroll", f, "UIPanelScrollFrameTemplate")
        lsf:SetPoint("TOPLEFT", 12, -44)
        lsf:SetPoint("BOTTOMLEFT", 12, 14)
        lsf:SetWidth(LEFT_SCROLL_W)

        local lcontent = CreateFrame("Frame", nil, lsf)
        lcontent:SetSize(LEFT_SCROLL_W, 1)

        local ltext = lcontent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        ltext:SetPoint("TOPLEFT", 0, 0)
        ltext:SetWidth(LEFT_TEXT_W)
        ltext:SetJustifyH("LEFT")
        ltext:SetJustifyV("TOP")
        ltext:SetSpacing(3)
        lsf:SetScrollChild(lcontent)
        f.adviceText    = ltext
        f.adviceContent = lcontent

        -- Vertical separator.
        local sep = f:CreateTexture(nil, "ARTWORK")
        sep:SetColorTexture(1, 1, 1, 0.08)
        sep:SetPoint("TOPLEFT", LEFT_RIGHT, -44)
        sep:SetPoint("BOTTOMLEFT", LEFT_RIGHT, 14)
        sep:SetWidth(1)

        -- RIGHT column: report header + copy/paste edit box.
        local rhead = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        rhead:SetPoint("TOPLEFT", LEFT_RIGHT + 16, -46)
        rhead:SetText(L.PANEL_REPORT_HEADER)

        local rsf = CreateFrame("ScrollFrame", "StutterAlertExportScroll", f, "UIPanelScrollFrameTemplate")
        rsf:SetPoint("TOPLEFT", LEFT_RIGHT + 16, -68)
        rsf:SetPoint("BOTTOMRIGHT", -30, 14)

        local eb = CreateFrame("EditBox", nil, rsf)
        eb:SetMultiLine(true)
        eb:SetFontObject(ChatFontNormal)
        eb:SetAutoFocus(false)
        eb:SetWidth(220)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() f:Hide() end)
        eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        rsf:SetScrollChild(eb)
        f.editBox = eb

        tinsert(UISpecialFrames, "StutterAlertPanel")
        self.panelFrame = f
    end

    local f = self.panelFrame

    -- Left: refresh the advice and size the scroll child to fit it.
    f.adviceText:SetText(ns.Advisor:BuildAdviceText())
    f.adviceContent:SetHeight((f.adviceText:GetStringHeight() or 0) + 8)

    -- Right: refresh the report. Highlight for copy only out of combat (focusing
    -- an edit box is fine in combat, but we avoid stealing focus mid-fight).
    f.editBox:SetText(self:BuildExportReport())
    f:Show()
    if not InCombatLockdown() then
        f.editBox:SetFocus()
        f.editBox:HighlightText()
    end
    f.editBox:SetCursorPosition(0)
end

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------
function Overlay:ShowPreview()
    if not frame then return end
    -- Flash a short summary-style toast so the player can see where banners
    -- appear for the current growth direction.
    self:PushSummaryToast(L.PREVIEW_MODE, COLOR[STATE.ELEVATED], 4)
end

function Overlay:Create()
    local s = DB.settings
    local initialSize = s.buttonSize
    if initialSize == "DEFAULT" or not initialSize then initialSize = 32 end

    -- 1. The Anchor Button (Back to Frame to dodge skinning addons and native button borders)
    frame = CreateFrame("Frame", "StutterAlertOverlay", UIParent)
    frame:SetSize(initialSize, initialSize)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(100)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")

    -- The Tinted Logo (No background box, just the pure logo)
    bg = frame:CreateTexture(nil, "ARTWORK")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\AddOns\\StutterAlert\\Media\\sabutton.tga")
    local c = COLOR[STATE.CALM]
    bg:SetVertexColor(c[1], c[2], c[3], 1.0)

    -- Hide the old dot, relying on colored logo logic
    if not dot then dot = frame:CreateTexture(nil, "OVERLAY") end
    dot:Hide()

    -- Pre-warm the toast pool so we don't create frames mid-combat.
    for _ = 1, (s.bannerStackMax or 4) + 1 do
        toastPool[#toastPool + 1] = createToastFrame()
    end

    -- Pulse strictly on the Anchor Button
    pulse = frame:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local a = pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(1.0)
    a:SetToAlpha(0.45)
    a:SetDuration(0.4)

    frame:SetScript("OnDragStart", function(self)
        if not DB.settings.locked then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition()
        -- Force a layout refresh immediately if toasts are active while dragging
        if #toasts > 0 then
            ns.Overlay:LayoutToasts()
        end
    end)

    -- Handle native dropdown and click overrides using OnMouseUp on the Frame
    frame:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            MenuUtil.CreateContextMenu(self, function(owner, rootDescription)
                rootDescription:CreateTitle(L.MENU_TITLE)

                -- Growth Direction Submenu
                local growthMenu = rootDescription:CreateButton(L.MENU_GROWTH_DIR)
                local function setGrowth(dir)
                    DB.settings.bannerGrowthOverride = dir
                    if #toasts > 0 then ns.Overlay:LayoutToasts() end
                    ns.Overlay:ShowPreview()
                end

                growthMenu:CreateRadio(L.MENU_GROWTH_AUTO, function() return DB.settings.bannerGrowthOverride == "AUTO" end, function() setGrowth("AUTO") end)
                growthMenu:CreateRadio(L.MENU_GROWTH_LU, function() return DB.settings.bannerGrowthOverride == "LEFT_UP" end, function() setGrowth("LEFT_UP") end)
                growthMenu:CreateRadio(L.MENU_GROWTH_LD, function() return DB.settings.bannerGrowthOverride == "LEFT_DOWN" end, function() setGrowth("LEFT_DOWN") end)
                growthMenu:CreateRadio(L.MENU_GROWTH_RU, function() return DB.settings.bannerGrowthOverride == "RIGHT_UP" end, function() setGrowth("RIGHT_UP") end)
                growthMenu:CreateRadio(L.MENU_GROWTH_RD, function() return DB.settings.bannerGrowthOverride == "RIGHT_DOWN" end, function() setGrowth("RIGHT_DOWN") end)

                -- Size Submenu
                local sizeMenu = rootDescription:CreateButton(L.MENU_SIZE)
                sizeMenu:CreateRadio(L.MENU_SIZE_DEFAULT, function() return DB.settings.buttonSize == "DEFAULT" or DB.settings.buttonSize == nil end, function() DB.settings.buttonSize = "DEFAULT" ns.Overlay:RestorePosition() end)
                sizeMenu:CreateRadio(L.MENU_SIZE_S, function() return DB.settings.buttonSize == 32 end, function() DB.settings.buttonSize = 32 ns.Overlay:RestorePosition() end)
                sizeMenu:CreateRadio(L.MENU_SIZE_M, function() return DB.settings.buttonSize == 64 end, function() DB.settings.buttonSize = 64 ns.Overlay:RestorePosition() end)

                rootDescription:CreateDivider()

                -- Actions
                rootDescription:CreateCheckbox(L.MENU_LOCK, function() return DB.settings.locked end, function() ns.Overlay:SetLocked(not DB.settings.locked) end)
                rootDescription:CreateButton(L.MENU_RESET, function() ns.Overlay:ResetPosition() end)
                rootDescription:CreateButton(L.MENU_CLEAR_HIST, function()
                    DB:ClearHistory()
                    if GameTooltip:IsOwned(self) then
                        GameTooltip:Hide()
                        showTooltip()
                    end
                end)
            end)
        elseif button == "LeftButton" and IsShiftKeyDown() then
            DB:ClearHistory()
            if GameTooltip:IsOwned(self) then
                GameTooltip:Hide()
                showTooltip()
            end
        elseif button == "LeftButton" and DB.settings.locked then
            ns.Overlay:ShowExport()
        end
    end)

    frame:SetScript("OnEnter", showTooltip)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Hook LFG eye visibility to trigger a reposition, preventing collisions dynamically
    if QueueStatusButton then
        hooksecurefunc(QueueStatusButton, "Show", function() ns.Overlay:RestorePosition() end)
        hooksecurefunc(QueueStatusButton, "Hide", function() ns.Overlay:RestorePosition() end)
    end

    self:RestorePosition()
    self:UpdateMouse()
end

-- ---------------------------------------------------------------------------
-- Re-dock when the screen size / UI scale changes, and after each loading
-- screen (so it settles once other UI addons, e.g. ElvUI, have finished
-- positioning the micro menu). These events are not taint-sensitive.
-- ---------------------------------------------------------------------------
local anchorWatcher = CreateFrame("Frame")
anchorWatcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
anchorWatcher:RegisterEvent("UI_SCALE_CHANGED")
anchorWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
anchorWatcher:SetScript("OnEvent", function()
    Overlay:RestorePosition()
end)
