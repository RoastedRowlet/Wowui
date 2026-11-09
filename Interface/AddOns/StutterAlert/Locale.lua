local _, ns = ...

-- Localization table. A missing key reads as its own name, never nil, so a gap
-- shows in-game instead of erroring.

local L = setmetatable({}, {
    __index = function(_, key)
        return key
    end,
})

ns.L = L
