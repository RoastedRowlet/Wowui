local _, ns = ...

-- ---------------------------------------------------------------------------
-- Which client is this?
--
-- One codebase runs on retail and on the Classic progression clients. That is
-- possible because C_AddOnProfiler -- the per-frame read this whole addon is
-- built on -- is present and COMPLETE on all of them: nine functions and all
-- twelve Enum.AddOnProfilerMetric fields, with identical numbering, verified
-- directly on 12.1.5, MoP 5.5.4 (69585), BC Anniversary 2.5.6 (69546) and
-- Classic Era 1.15.9 (69547) on 2026-09-07. Detection, attribution, the event
-- ring, signatures and the throttle-regime test therefore need no branching at
-- all, and there is none.
--
-- Two things do differ, and they are the only reasons this file exists:
--   1. Retail is the only client with Mythic+, so it is the only one whose
--      five-man context label should mention it (see Constants.lua).
--   2. A pasted report should name the game it came from. "5.5.4" is not
--      self-explanatory to whoever reads it (see Overlay.lua).
--
-- Everything else that varies -- notably which graphics console variables
-- exist -- is decided by probing for it, not by asking which client this is.
-- Capability beats identity: it keeps working when Blizzard backports the next
-- thing, exactly as they backported the profiler.
-- ---------------------------------------------------------------------------

-- The documented WOW_PROJECT_* constants. A client only defines the ones it
-- knows about, so an Era client has no WOW_PROJECT_MISTS_CLASSIC and every
-- comparison has to tolerate nil rather than assume the global is there.
local projectID = rawget(_G, "WOW_PROJECT_ID")

local function isProject(globalName)
    local want = rawget(_G, globalName)
    return want ~= nil and projectID ~= nil and projectID == want
end

ns.PROJECT_ID = projectID

-- Retail. Used for the Mythic+ wording and nothing else.
ns.IsRetail = isProject("WOW_PROJECT_MAINLINE")

-- Project constant -> locale key naming the client in the pasted report.
-- Deliberately an ordered array, not a hash: a pairs() walk would pick a
-- different entry between runs whenever two ids somehow matched, and this
-- string ends up in reports players compare against each other.
local FLAVOR_KEYS = {
    { "WOW_PROJECT_MAINLINE",                "FLAVOR_RETAIL"       },
    { "WOW_PROJECT_MISTS_CLASSIC",           "FLAVOR_MISTS"        },
    { "WOW_PROJECT_CATACLYSM_CLASSIC",       "FLAVOR_CATA"         },
    { "WOW_PROJECT_WRATH_CLASSIC",           "FLAVOR_WRATH"        },
    { "WOW_PROJECT_BURNING_CRUSADE_CLASSIC", "FLAVOR_TBC"          },
    { "WOW_PROJECT_CLASSIC",                 "FLAVOR_CLASSIC_ERA"  },
}

-- nil on a client we have no name for. Callers fall back to the unnamed client
-- line rather than inventing a label for a project that did not exist yet.
for i = 1, #FLAVOR_KEYS do
    if isProject(FLAVOR_KEYS[i][1]) then
        ns.FLAVOR_KEY = FLAVOR_KEYS[i][2]
        break
    end
end
