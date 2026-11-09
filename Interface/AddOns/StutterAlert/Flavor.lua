local _, ns = ...

-- ---------------------------------------------------------------------------
-- Which client is this? Used only for the Mythic+ wording and the report's game
-- name; everything else probes. See DESIGN-NOTES.md: Profiler on every client.
-- ---------------------------------------------------------------------------

-- A client defines only the WOW_PROJECT_* constants it knows, so every
-- comparison must tolerate nil.
local projectID = rawget(_G, "WOW_PROJECT_ID")

local function isProject(globalName)
    local want = rawget(_G, globalName)
    return want ~= nil and projectID ~= nil and projectID == want
end

ns.PROJECT_ID = projectID

-- Retail. Used for the Mythic+ wording and nothing else.
ns.IsRetail = isProject("WOW_PROJECT_MAINLINE")

-- Project constant to the locale key naming the game in the report. An ordered
-- array, not a hash, so a tie resolves the same way every run.
local FLAVOR_KEYS = {
    { "WOW_PROJECT_MAINLINE",                "FLAVOR_RETAIL"       },
    { "WOW_PROJECT_MISTS_CLASSIC",           "FLAVOR_MISTS"        },
    { "WOW_PROJECT_CATACLYSM_CLASSIC",       "FLAVOR_CATA"         },
    { "WOW_PROJECT_WRATH_CLASSIC",           "FLAVOR_WRATH"        },
    { "WOW_PROJECT_BURNING_CRUSADE_CLASSIC", "FLAVOR_TBC"          },
    { "WOW_PROJECT_CLASSIC",                 "FLAVOR_CLASSIC_ERA"  },
    { "WOW_PROJECT_CAMELOT",                 "FLAVOR_FOREVER"      },
}

-- nil on a client we have no name for. Callers fall back to the unnamed client
-- line rather than inventing a label for a project that did not exist yet.
for i = 1, #FLAVOR_KEYS do
    if isProject(FLAVOR_KEYS[i][1]) then
        ns.FLAVOR_KEY = FLAVOR_KEYS[i][2]
        break
    end
end
