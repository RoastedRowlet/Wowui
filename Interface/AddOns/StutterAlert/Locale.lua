local _, ns = ...

-- Localization table.
--
-- Design rule for this addon: NO hardcoded UI strings anywhere in Core/UI code.
-- Every user-facing string is referenced as L.SOME_KEY and defined in a
-- Locales/<locale>.lua file. enUS.lua is the always-loaded base; other locales
-- override individual keys.
--
-- The metatable below guarantees two things:
--   1. Reading a missing key never errors (no nil concatenation crashes).
--   2. A missing translation renders as its KEY name in-game, making gaps
--      obvious during testing instead of silently falling back to English.
--
-- This is a key-name fallback, not a hardcoded-string fallback: there is no
-- English literal sitting at the call site to mask a missing entry.

local L = setmetatable({}, {
    __index = function(_, key)
        return key
    end,
})

ns.L = L
